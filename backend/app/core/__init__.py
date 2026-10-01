"""Core package for application configuration, logging, database, and exceptions."""

from backend.app.core.config import Settings, get_settings
from backend.app.core.database import db_manager, get_database
from backend.app.core.exceptions import (
    DatabaseConnectionError,
    IFSOException,
    InvalidStateTransitionError,
    ResourceNotFoundError,
    ValidationException,
    register_exception_handlers,
)
from backend.app.core.logging import get_logger, mask_phone_number, setup_logging

__all__ = [
    "Settings",
    "get_settings",
    "db_manager",
    "get_database",
    "IFSOException",
    "DatabaseConnectionError",
    "ResourceNotFoundError",
    "InvalidStateTransitionError",
    "ValidationException",
    "register_exception_handlers",
    "get_logger",
    "mask_phone_number",
    "setup_logging",
]
