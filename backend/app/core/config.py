"""Application Configuration Module.

Loads settings from environment variables and provides centralized access
using pydantic-settings.
"""

from functools import lru_cache
from typing import Literal
from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Core application settings."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # Application metadata
    app_name: str = Field(
        default="IFSO Location Request Management System",
        description="Application title",
    )
    app_env: Literal["development", "testing", "staging", "production"] = Field(
        default="development",
        description="Application environment",
    )
    app_debug: bool = Field(
        default=True,
        description="Debug flag for development",
    )
    app_version: str = Field(
        default="0.1.0",
        description="Current application version",
    )
    log_level: str = Field(
        default="INFO",
        description="Logging level (DEBUG, INFO, WARNING, ERROR, CRITICAL)",
    )

    # API Server configuration
    host: str = Field(default="0.0.0.0", description="Bind host")
    port: int = Field(default=8000, description="Bind port")
    api_v1_prefix: str = Field(default="/api/v1", description="API v1 route prefix")

    # MongoDB configuration
    mongodb_uri: str = Field(
        default="mongodb://localhost:27017",
        description="MongoDB connection string",
    )
    mongodb_database: str = Field(
        default="ifso_location_dev",
        description="MongoDB database name",
    )
    mongodb_min_pool_size: int = Field(default=10, description="Connection pool minimum")
    mongodb_max_pool_size: int = Field(default=50, description="Connection pool maximum")
    mongodb_timeout_ms: int = Field(default=3000, description="Connection timeout in ms")

    # Security configuration (Phase 2+ Auth Placeholder)
    secret_key: str = Field(
        default="insecure-dev-key-change-in-production-only-for-local-testing",
        description="Secret key for signing / cryptographic operations",
    )
    access_token_expire_minutes: int = Field(
        default=60,
        description="Access token lifespan in minutes",
    )

    # Operational lifecycle configuration
    request_token_expire_hours: int = Field(
        default=24,
        description="Shareable token expiration window in hours",
    )
    sms_timeout_minutes: int = Field(
        default=5,
        description="Awaiting response timeout window in minutes",
    )
    max_sms_retries: int = Field(
        default=2,
        description="Maximum retry attempts on SMS transmission failure",
    )


@lru_cache
def get_settings() -> Settings:
    """Return cached application settings singleton."""
    return Settings()
