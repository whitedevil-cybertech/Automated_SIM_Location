"""Audit Log Document Model for MongoDB.

Ensures tamper-evident chain-of-custody logging for all actions and transitions
across the request lifecycle.
"""

from datetime import datetime, timezone
from typing import Any, Dict, Optional
import uuid
from pydantic import BaseModel, Field

from backend.app.models.enums import AuditEventType, UserRole


class AuditLogDocument(BaseModel):
    """MongoDB Document Model for the 'audit_logs' collection."""

    audit_id: str = Field(
        default_factory=lambda: f"AUD-{uuid.uuid4().hex[:12].upper()}",
        description="Unique tamper-evident audit identifier",
    )
    request_id: Optional[str] = Field(
        default=None, description="Associated location request ID if applicable"
    )
    timestamp: datetime = Field(
        default_factory=lambda: datetime.now(timezone.utc),
        description="Immutable UTC timestamp of event",
    )
    actor_id: str = Field(description="User ID or badge of the actor performing action")
    actor_role: UserRole = Field(description="Role of the actor at event execution")
    event_type: AuditEventType = Field(description="Categorized audit event type")
    details: Dict[str, Any] = Field(
        default_factory=dict, description="Structured contextual event metadata"
    )
    ip_address: Optional[str] = Field(
        default=None, description="Client IP address where available"
    )
    device_id: Optional[str] = Field(
        default=None, description="Client device fingerprint where available"
    )
