"""Operator Document Model for MongoDB.

Defines operator profiles and configuration rules. Real carrier shortcodes
and SMS templates are NOT hardcoded or guessed; they are maintained via
configurable database profiles.
"""

from datetime import datetime, timezone
from typing import Optional
from pydantic import BaseModel, Field


class OperatorDocument(BaseModel):
    """MongoDB Document Model for the 'operators' collection."""

    operator_code: str = Field(
        description="Unique operator identifier, e.g. JIO, AIRTEL, VI, BSNL"
    )
    display_name: str = Field(description="Human-readable carrier name")
    is_active: bool = Field(default=True, description="Whether profile is selectable")
    service_number: Optional[str] = Field(
        default=None,
        description="Carrier shortcode/service number (configured securely, not hardcoded)",
    )
    sms_template: Optional[str] = Field(
        default=None,
        description="Carrier SMS command syntax template, e.g. 'LOC {normalized_number}'",
    )
    notes: Optional[str] = Field(
        default=None, description="Operational instructions or notes"
    )
    created_at: datetime = Field(
        default_factory=lambda: datetime.now(timezone.utc),
        description="Creation timestamp",
    )
    updated_at: datetime = Field(
        default_factory=lambda: datetime.now(timezone.utc),
        description="Last update timestamp",
    )
