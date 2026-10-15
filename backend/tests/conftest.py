"""Pytest fixtures using the real PostgreSQL test database.

The test process is deliberately redirected to ifso_location_test before importing
the application. The fixture refuses to run against any other database.
"""
from __future__ import annotations

import asyncio
import os
import sys
import json
from pathlib import Path
from typing import Any

import pytest
import pytest_asyncio
from sqlalchemy import text
from sqlalchemy.engine import make_url
from httpx import ASGITransport, AsyncClient

# psycopg's async driver requires SelectorEventLoop on Windows.
if sys.platform == "win32":
    asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())

# Ensure the project root is importable.
PROJECT_ROOT = Path(__file__).resolve().parents[2]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

# Derive the test URL from the configured URL without hardcoding credentials.
# The source URL must point to the project's known local databases.
from backend.app.core.config import Settings, get_settings

_source_settings = Settings()
_source_url = make_url(_source_settings.database_url)
if _source_url.database not in {"ifso_location", "ifso_location_test"}:
    raise RuntimeError(
        "Refusing to run tests: DATABASE_URL must target ifso_location "
        "or ifso_location_test before test redirection."
    )

_test_url = _source_url.set(database="ifso_location_test")
os.environ["DATABASE_URL"] = _test_url.render_as_string(hide_password=False)
os.environ["DATABASE_NAME"] = "ifso_location_test"
os.environ["APP_ENV"] = "testing"
os.environ["APP_DEBUG"] = "true"
os.environ["DEVELOPMENT_AUTH_TOKENS"] = json.dumps({
    "test-officer-token": "OFFICER-DEV-001:OFFICER",
    "test-io-token": "IO-DEV-001:IO",
    "test-admin-token": "ADMIN-DEV-001:ADMIN",
})
get_settings.cache_clear()

# Import only after DATABASE_URL has been redirected.
from backend.app.core.database import db_manager
from backend.app.main import create_application


@pytest.fixture(scope="session")
def test_settings() -> Settings:
    """Settings for tests, always targeting the dedicated test database."""
    settings = get_settings()
    parsed = make_url(settings.database_url)
    if parsed.database != "ifso_location_test":
        raise RuntimeError(
            f"Unsafe test database {parsed.database!r}; expected 'ifso_location_test'."
        )
    return settings


@pytest_asyncio.fixture
async def async_client(test_settings: Settings) -> AsyncClient:
    """Run FastAPI's actual startup/shutdown lifecycle for each test."""
    app = create_application()
    async with app.router.lifespan_context(app):
        if not db_manager.is_connected:
            raise RuntimeError(
                "PostgreSQL test database did not connect. "
                "Check DATABASE_URL and PostgreSQL service status."
            )
        async with db_manager.engine.connect() as connection:
            row = await connection.execute(text("SELECT current_database()"))
            actual_database = row.scalar_one()
        if actual_database != "ifso_location_test":
            raise RuntimeError(
                f"Refusing tests against {actual_database!r}; "
                "expected 'ifso_location_test'."
            )
        transport = ASGITransport(app=app)
        async with AsyncClient(
            transport=transport, base_url="http://testserver"
        ) as client:
            yield client


@pytest_asyncio.fixture
async def postgres_database(async_client: AsyncClient):
    """Expose the real database manager and isolate records for each test.

    Depends on async_client so FastAPI startup has initialized the connection pool.
    Deletes only rows in the dedicated test database.
    """
    if db_manager.engine is None or not db_manager.is_connected:
        raise RuntimeError("PostgreSQL is not connected.")

    async with db_manager.engine.begin() as connection:
        database_name = (
            await connection.execute(text("SELECT current_database()"))
        ).scalar_one()
        if database_name != "ifso_location_test":
            raise RuntimeError("Refusing to clean a non-test database.")
        # Delete children/audit records first. This database is reserved for tests.
        await connection.execute(text("DELETE FROM audit_logs"))
        await connection.execute(text("DELETE FROM location_requests"))
        await connection.execute(text("DELETE FROM operators"))

    yield db_manager

    if db_manager.engine is not None and db_manager.is_connected:
        async with db_manager.engine.begin() as connection:
            database_name = (
                await connection.execute(text("SELECT current_database()"))
            ).scalar_one()
            if database_name != "ifso_location_test":
                raise RuntimeError("Refusing cleanup against a non-test database.")
            await connection.execute(text("DELETE FROM audit_logs"))
            await connection.execute(text("DELETE FROM location_requests"))
            await connection.execute(text("DELETE FROM operators"))


async def fetch_all_documents(collection) -> list[dict[str, Any]]:
    """Read all persisted payloads from a real PostgresCollection."""
    return await collection._find({}, None)
