"""MongoDB Database Connection and Collection Abstractions.

Provides asynchronous MongoDB client management using Motor with connection pooling,
graceful offline handling, and safe health-check diagnostics.
"""

from typing import Any, Dict, Optional
from motor.motor_asyncio import AsyncIOMotorClient, AsyncIOMotorCollection, AsyncIOMotorDatabase
from pymongo.errors import ConnectionFailure, ServerSelectionTimeoutError

from backend.app.core.config import Settings, get_settings
from backend.app.core.exceptions import DatabaseConnectionError
from backend.app.core.logging import get_logger

logger = get_logger(__name__)


class DatabaseManager:
    """Manages MongoDB client lifecycle and provides access to collections."""

    def __init__(self) -> None:
        self.client: Optional[AsyncIOMotorClient] = None
        self.db: Optional[AsyncIOMotorDatabase] = None
        self.is_connected: bool = False

    async def connect(self, settings: Optional[Settings] = None) -> bool:
        """Initialize Motor client and attempt a ping check.

        Does not raise an exception if MongoDB is unavailable; logs a clear
        warning and allows the server to run in degraded/mock mode.
        """
        cfg = settings or get_settings()

        try:
            logger.info("Initializing MongoDB client connection...")
            self.client = AsyncIOMotorClient(
                cfg.mongodb_uri,
                minPoolSize=cfg.mongodb_min_pool_size,
                maxPoolSize=cfg.mongodb_max_pool_size,
                serverSelectionTimeoutMS=cfg.mongodb_timeout_ms,
            )
            self.db = self.client[cfg.mongodb_database]

            # Verify connection with quick ping
            await self.client.admin.command("ping")
            self.is_connected = True
            logger.info(
                f"Successfully connected to MongoDB database '{cfg.mongodb_database}'."
            )
            return True
        except (ConnectionFailure, ServerSelectionTimeoutError) as exc:
            self.is_connected = False
            logger.warning(
                f"MongoDB service is unavailable ({type(exc).__name__}). "
                "Running in degraded/offline database mode."
            )
            return False
        except Exception as exc:
            self.is_connected = False
            logger.warning(
                f"Unexpected error while initializing MongoDB: {exc}. "
                "Running in degraded/offline database mode."
            )
            return False

    async def close(self) -> None:
        """Close MongoDB client connection pool."""
        if self.client:
            logger.info("Closing MongoDB client connection pool.")
            self.client.close()
            self.client = None
            self.db = None
            self.is_connected = False

    async def check_health(self) -> Dict[str, Any]:
        """Perform a live ping check against the database."""
        if not self.client:
            return {
                "status": "disconnected",
                "message": "Database client has not been initialized.",
            }

        try:
            await self.client.admin.command("ping")
            self.is_connected = True
            return {
                "status": "connected",
                "database": self.db.name if self.db is not None else None,
            }
        except Exception as exc:
            self.is_connected = False
            return {
                "status": "disconnected",
                "message": f"Connection check failed: {type(exc).__name__}",
            }

    def get_database(self) -> AsyncIOMotorDatabase:
        """Retrieve active database instance or raise DatabaseConnectionError."""
        if self.db is None or not self.is_connected:
            raise DatabaseConnectionError(
                "MongoDB database instance is not initialized or unavailable."
            )
        return self.db

    # Logical collection accessors
    @property
    def location_requests(self) -> AsyncIOMotorCollection:
        """Collection accessor for location_requests."""
        return self.get_database()["location_requests"]

    @property
    def operators(self) -> AsyncIOMotorCollection:
        """Collection accessor for operators."""
        return self.get_database()["operators"]

    @property
    def audit_logs(self) -> AsyncIOMotorCollection:
        """Collection accessor for audit_logs."""
        return self.get_database()["audit_logs"]


# Global database manager singleton
db_manager = DatabaseManager()


async def get_database() -> AsyncIOMotorDatabase:
    """Dependency helper to inject active database."""
    return db_manager.get_database()
