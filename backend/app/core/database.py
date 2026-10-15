"""Async PostgreSQL persistence adapter.

The adapter intentionally preserves the existing collection-style call surface used by
routes while executing all persistence through SQLAlchemy 2.x and psycopg 3.
Payloads retain the existing serialized Pydantic document shape; indexed relational
columns enforce identifiers and support common lookups. Nested fields remain JSONB
because they are existing structured lifecycle objects.
"""
from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, Optional
from sqlalchemy import (
    MetaData, Table, Column, String, DateTime, Boolean, select, insert, update,
    text, Index,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.exc import SQLAlchemyError

from backend.app.core.config import Settings, get_settings
from backend.app.core.exceptions import DatabaseConnectionError
from backend.app.core.logging import get_logger

logger = get_logger(__name__)
metadata = MetaData()

location_requests_table = Table(
    "location_requests", metadata,
    Column("request_id", String(80), primary_key=True),
    Column("case_id", String(255), nullable=False),
    Column("status", String(64), nullable=False, index=True),
    Column("operator_code", String(32), nullable=False, index=True),
    Column("submitting_officer_id", String(255), nullable=False, index=True),
    Column("share_token_hash", String(64), unique=True, nullable=True),
    Column("created_at", DateTime(timezone=True), nullable=False, index=True),
    Column("updated_at", DateTime(timezone=True), nullable=False),
    Column("payload", JSONB, nullable=False),
)
Index("ix_location_requests_status_created", location_requests_table.c.status, location_requests_table.c.created_at)

operators_table = Table(
    "operators", metadata,
    Column("operator_code", String(32), primary_key=True),
    Column("is_active", Boolean, nullable=False, server_default=text("true")),
    Column("payload", JSONB, nullable=False),
)
audit_logs_table = Table(
    "audit_logs", metadata,
    Column("audit_id", String(80), primary_key=True),
    Column("request_id", String(80), nullable=True),
    Column("timestamp", DateTime(timezone=True), nullable=False, index=True),
    Column("actor_id", String(255), nullable=False, index=True),
    Column("event_type", String(80), nullable=False, index=True),
    Column("payload", JSONB, nullable=False),
)

TABLES = {
    "location_requests": location_requests_table,
    "operators": operators_table,
    "audit_logs": audit_logs_table,
}

def _nested(data: dict, path: str):
    cur = data
    for part in path.split("."):
        if not isinstance(cur, dict) or part not in cur:
            return None
        cur = cur[part]
    return cur

def _matches(data: dict, query: dict) -> bool:
    for key, expected in query.items():
        if _nested(data, key) != expected:
            return False
    return True

def _flatten_payload(payload: dict, table: Table) -> dict:
    p = dict(payload)
    if table is location_requests_table:
        token = p.get("share_token") or {}
        return {
            "request_id": p["request_id"], "case_id": p["case_id"],
            "status": getattr(p.get("status"), "value", p.get("status", "CREATED")),
            "operator_code": p["operator_code"],
            "submitting_officer_id": p["submitting_officer_id"],
            "share_token_hash": token.get("token_hash"),
            "created_at": _dt(p.get("created_at")), "updated_at": _dt(p.get("updated_at")),
            "payload": p,
        }
    if table is operators_table:
        return {"operator_code": p["operator_code"], "is_active": bool(p.get("is_active", True)), "payload": p}
    return {
        "audit_id": p["audit_id"], "request_id": p.get("request_id"),
        "timestamp": _dt(p.get("timestamp")), "actor_id": p["actor_id"],
        "event_type": getattr(p.get("event_type"), "value", p.get("event_type")),
        "payload": p,
    }

def _dt(value):
    if isinstance(value, datetime):
        return value
    if isinstance(value, str):
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    return value

def _document(row):
    if row is None:
        return None
    payload = dict(row["payload"])
    return payload

class AsyncCursor:
    def __init__(self, collection, query):
        self.collection, self.query, self.order = collection, query, None
    def sort(self, key, direction):
        self.order = (key, direction)
        return self
    def __aiter__(self):
        async def iterator():
            for item in await self.collection._find(self.query, self.order):
                yield item
        return iterator()

class PostgresCollection:
    def __init__(self, manager, name):
        self.manager, self.name, self.table = manager, name, TABLES[name]
    async def insert_one(self, document):
        async with self.manager.sessions() as session:
            async with session.begin():
                await session.execute(insert(self.table).values(**_flatten_payload(document, self.table)))
        return type("InsertResult", (), {"inserted_id": document.get("request_id", document.get("audit_id", document.get("operator_code")))})()
    async def find_one(self, query, projection=None):
        rows = await self._find(query, None, limit=1)
        return rows[0] if rows else None
    def find(self, query):
        return AsyncCursor(self, query)
    def _conditions(self, query):
        conditions = []
        for key, value in query.items():
            mapped = {"share_token.token_hash": "share_token_hash"}.get(key, key)
            if mapped in self.table.c:
                conditions.append(self.table.c[mapped] == value)
        return conditions

    async def _find(self, query, order, limit=None):
        async with self.manager.sessions() as session:
            stmt = select(self.table).where(*self._conditions(query))
            result = await session.execute(stmt)
            docs = []
            for row in result.mappings():
                doc = _document(row)
                if _matches(doc, query):
                    docs.append(doc)
            if order:
                key, direction = order
                docs.sort(key=lambda d: _nested(d, key) or "", reverse=direction < 0)
            return docs[:limit] if limit else docs
    async def update_one(self, query, update_doc):
        # Serialize candidate selection/update in one transaction. Row-level locking
        # prevents concurrent lifecycle transitions from overwriting one another.
        async with self.manager.sessions() as session:
            async with session.begin():
                stmt = select(self.table).where(*self._conditions(query)).with_for_update()
                result = await session.execute(stmt)
                for row in result.mappings():
                    doc = _document(row)
                    if not _matches(doc, query):
                        continue
                    for path, value in update_doc.get("$set", {}).items():
                        cur = doc
                        parts = path.split(".")
                        for part in parts[:-1]:
                            if not isinstance(cur.get(part), dict):
                                cur[part] = {}
                            cur = cur[part]
                        cur[parts[-1]] = value.isoformat() if isinstance(value, datetime) else value
                    vals = _flatten_payload(doc, self.table)
                    key_col = list(self.table.primary_key.columns)[0]
                    key = row[key_col.name]
                    await session.execute(update(self.table).where(key_col == key).values(**vals))
                    return type("UpdateResult", (), {"modified_count": 1})()
        return type("UpdateResult", (), {"modified_count": 0})()

class DatabaseManager:
    def __init__(self):
        self.engine: Optional[AsyncEngine] = None
        self.sessions = None
        self.is_connected = False
        self._collections = {name: PostgresCollection(self, name) for name in TABLES}
    async def connect(self, settings: Optional[Settings] = None) -> bool:
        cfg = settings or get_settings()
        try:
            self.engine = create_async_engine(
                cfg.database_url,
                pool_size=cfg.database_pool_size,
                max_overflow=cfg.database_max_overflow,
                pool_timeout=cfg.database_pool_timeout_seconds,
                pool_pre_ping=True,
            )
            self.sessions = async_sessionmaker(self.engine, expire_on_commit=False, class_=AsyncSession)
            async with self.engine.connect() as conn:
                await conn.execute(text("SELECT 1"))
            self.is_connected = True
            logger.info("Connected to PostgreSQL.")
            return True
        except Exception as exc:
            self.is_connected = False
            logger.warning("PostgreSQL unavailable (%s); running in degraded/offline mode.", type(exc).__name__)
            return False
    async def close(self):
        if self.engine is not None:
            await self.engine.dispose()
        self.engine = None
        self.sessions = None
        self.is_connected = False
    async def check_health(self) -> Dict[str, Any]:
        if self.engine is None or self.sessions is None:
            return {"status": "disconnected", "message": "Database engine has not been initialized."}
        try:
            async with self.engine.connect() as conn:
                await conn.execute(text("SELECT 1"))
            self.is_connected = True
            return {"status": "connected", "database": get_settings().database_name}
        except Exception as exc:
            self.is_connected = False
            return {"status": "disconnected", "message": f"Connection check failed: {type(exc).__name__}"}
    def get_database(self):
        if not self.is_connected or self.sessions is None:
            raise DatabaseConnectionError("PostgreSQL database is not initialized or unavailable.")
        return self
    @property
    def location_requests(self):
        db = self.get_database()
        return db._collections["location_requests"] if db is self else db["location_requests"]
    @property
    def operators(self):
        db = self.get_database()
        return db._collections["operators"] if db is self else db["operators"]
    @property
    def audit_logs(self):
        db = self.get_database()
        return db._collections["audit_logs"] if db is self else db["audit_logs"]

db_manager = DatabaseManager()
async def get_database():
    return db_manager.get_database()
