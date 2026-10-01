"""Common API Response Envelopes and Base Schemas."""

from datetime import datetime, timezone
from typing import Any, Dict, Generic, Optional, TypeVar
from pydantic import BaseModel, Field

DataT = TypeVar("DataT")


class ApiResponse(BaseModel, Generic[DataT]):
    """Standard success API response envelope."""

    success: bool = Field(default=True, description="Indicates request success")
    message: Optional[str] = Field(
        default=None, description="Optional informational message"
    )
    data: Optional[DataT] = Field(
        default=None, description="Response payload content"
    )
    timestamp: datetime = Field(
        default_factory=lambda: datetime.now(timezone.utc),
        description="Response UTC timestamp",
    )


class ErrorDetail(BaseModel):
    """Detailed error structure."""

    code: str = Field(description="Machine-readable error identifier")
    message: str = Field(description="Human-readable error explanation")
    details: Dict[str, Any] = Field(
        default_factory=dict, description="Additional context or validation details"
    )


class ErrorResponse(BaseModel):
    """Standard error API response envelope."""

    success: bool = Field(default=False, description="Always False for errors")
    error: ErrorDetail = Field(description="Error details")
    timestamp: datetime = Field(
        default_factory=lambda: datetime.now(timezone.utc),
        description="Error UTC timestamp",
    )


class HealthStatusResponse(BaseModel):
    """System health endpoint response schema."""

    status: str = Field(description="Overall application health status")
    app: str = Field(description="Application title")
    version: str = Field(description="Application version")
    environment: str = Field(description="Current deployment environment")
    database: Dict[str, Any] = Field(description="Database connectivity diagnostics")
    timestamp: datetime = Field(
        default_factory=lambda: datetime.now(timezone.utc),
        description="Report timestamp",
    )
