"""Application Configuration Module.

Loads settings from environment variables and provides centralized access
using pydantic-settings.
"""

from functools import lru_cache
from typing import Dict, Literal, Optional, List
from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict
from pathlib import Path

class Settings(BaseSettings):
    """Core application settings."""

    model_config = SettingsConfigDict(
      env_file=Path(__file__).resolve().parents[2] / ".env",
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

    # PostgreSQL configuration
    database_url: str = Field(
        default="postgresql+psycopg://localhost:5432/ifso_location",
        description="SQLAlchemy async PostgreSQL URL; provide via DATABASE_URL.",
    )
    database_name: str = Field(default="ifso_location", description="Logical database name for health reporting")
    database_pool_size: int = Field(default=10, description="SQLAlchemy connection pool size")
    database_max_overflow: int = Field(default=20, description="Maximum overflow connections")
    database_pool_timeout_seconds: int = Field(default=3, description="Pool checkout timeout in seconds")

    # Security configuration (Phase 2+ Auth Placeholder)
    secret_key: str = Field(
        default="insecure-dev-key-change-in-production-only-for-local-testing",
        description="Secret key for signing / cryptographic operations",
    )
    access_token_expire_minutes: int = Field(
        default=60,
        description="Access token lifespan in minutes",
    )
    auth_mode: Literal["development_static", "external"] = Field(
        default="development_static",
        description=(
            "Authentication boundary. development_static is allowed only for "
            "development/testing; production must use an external identity provider."
        ),
    )
    external_auth_jwks_url: Optional[str] = Field(default=None, description="Trusted identity provider JWKS endpoint")
    external_auth_issuer: Optional[str] = Field(default=None, description="Expected JWT issuer")
    external_auth_audience: Optional[str] = Field(default=None, description="Expected JWT audience")
    external_auth_role_claim: str = Field(default="role", description="JWT claim containing a single application role")
    external_auth_subject_claim: str = Field(default="sub", description="JWT claim identifying the authenticated user")
    timeout_worker_interval_seconds: int = Field(default=30, ge=5, le=300, description="Polling interval for request timeout transitions")
    cors_allowed_origins: List[str] = Field(default_factory=list, description="Explicit browser origins; empty disables browser CORS")
    development_auth_tokens: Dict[str, str] = Field(
        default_factory=dict,
        description=(
            "Development-only bearer token mapping: token -> principal_id:ROLE. "
            "Never use as production authentication."
        ),
    )
    field_encryption_key: Optional[str] = Field(
        default=None,
        description=(
            "Fernet key used for reversible encryption of sensitive fields. "
            "Required outside development/testing."
        ),
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


@lru_cache
def get_settings() -> Settings:
    """Return cached application settings singleton."""
    return Settings()
