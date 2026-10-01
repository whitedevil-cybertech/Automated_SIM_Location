"""Base Service Abstraction.

Provides common utilities, structured logging references, and database
access handles for domain services.
"""

from typing import Optional
from motor.motor_asyncio import AsyncIOMotorDatabase
import logging

from backend.app.core.database import db_manager
from backend.app.core.logging import get_logger


class BaseService:
    """Base class for all business services."""

    def __init__(self, db: Optional[AsyncIOMotorDatabase] = None) -> None:
        self._db = db
        self.logger: logging.Logger = get_logger(self.__class__.__name__)

    @property
    def db(self) -> AsyncIOMotorDatabase:
        """Access active MongoDB instance via db_manager if not injected."""
        if self._db is not None:
            return self._db
        return db_manager.get_database()
