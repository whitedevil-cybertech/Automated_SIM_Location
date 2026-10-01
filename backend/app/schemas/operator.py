"""API Schemas for Telecom Operator Profiles."""

from typing import Optional
from pydantic import BaseModel, Field


class OperatorResponse(BaseModel):
    """Schema representing selectable telecom operators."""

    operator_code: str = Field(description="Carrier code, e.g. JIO, AIRTEL, VI, BSNL")
    display_name: str = Field(description="Human-readable carrier name")
    is_active: bool = Field(default=True, description="Whether active for new requests")
    notes: Optional[str] = Field(
        default=None, description="Guidance notes for investigating officers"
    )
