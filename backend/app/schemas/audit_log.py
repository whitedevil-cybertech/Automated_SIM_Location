"""API Schemas for Audit Log Records."""

from datetime import datetime
from typing import Any, Dict, Optional
from pydantic import BaseModel, Field

from backend.app.models.enums import AuditEventType, UserRole


class AuditLogResponse(BaseModel):
    """Schema representing an immutable audit log record."""

    audit_id: str = Field(description="Unique audit record identifier")
    request_id: Optional[str] = Field(
        default=None, description="Associated location request ID"
    )
    timestamp: datetime = Field(description="Event timestamp in UTC")
    actor_id: str = Field(description="Officer or IO user identifier")
    actor_role: UserRole = Field(description="Actor role")
    event_type: AuditEventType = Field(description="Event classification")
    details: Dict[str, Any] = Field(
        default_factory=dict, description="Contextual event payload"
    )
