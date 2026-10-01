"""API Schemas for Location Request Resources.

Provides validation for request creation, execution triggers, and response ingestion.
"""

from datetime import datetime
import re
from typing import Optional
from pydantic import BaseModel, Field, field_validator

from backend.app.models.enums import RequestState


class LocationRequestCreate(BaseModel):
    """Schema for creating a new location request (Officer input)."""

    case_id: str = Field(
        min_length=1,
        max_length=64,
        description="Case reference / FIR identifier",
        examples=["FIR-2026-IFSO-084"],
    )
    target_phone_number: str = Field(
        description="Target mobile number (10 digits or E.164 format with country code)",
        examples=["+919876543210"],
    )
    operator_code: str = Field(
        min_length=2,
        max_length=16,
        description="Telecom operator identifier code",
        examples=["JIO", "AIRTEL", "VI", "BSNL"],
    )
    remarks: Optional[str] = Field(
        default=None,
        max_length=500,
        description="Optional operational remarks or justification",
    )

    @field_validator("target_phone_number")
    @classmethod
    def validate_phone_number(cls, v: str) -> str:
        """Validate and normalize phone number format."""
        cleaned = re.sub(r"[\s-]", "", v)
        # Check standard 10-digit or 12-digit Indian / international numbers
        if not re.match(r"^(\+?91)?[6-9]\d{9}$", cleaned):
            raise ValueError(
                "Invalid phone number format. Must be a 10-digit mobile number or have a valid country code."
            )
        # Normalize to leading +91 if 10 digits
        if len(cleaned) == 10:
            return f"+91{cleaned}"
        if cleaned.startswith("91") and len(cleaned) == 12:
            return f"+{cleaned}"
        return cleaned

    @field_validator("operator_code")
    @classmethod
    def normalize_operator(cls, v: str) -> str:
        return v.upper().strip()

    @field_validator("case_id")
    @classmethod
    def clean_case_id(cls, v: str) -> str:
        stripped = v.strip()
        if not stripped:
            raise ValueError("Case ID cannot be empty.")
        return stripped


class LocationRequestResponse(BaseModel):
    """Schema for public/authenticated retrieval of request details.

    Target number is ALWAYS masked to preserve evidentiary privacy.
    """

    request_id: str = Field(description="Unique opaque request identifier")
    case_id: str = Field(description="Case reference identifier")
    target_phone_masked: str = Field(
        description="Masked target phone number (middle digits redacted)"
    )
    operator_code: str = Field(description="Operator identifier code")
    submitting_officer_id: str = Field(description="Officer who created the request")
    executing_io_id: Optional[str] = Field(
        default=None, description="Assigned or executing IO"
    )
    status: RequestState = Field(description="Current lifecycle state")
    created_at: datetime = Field(description="Creation UTC timestamp")
    updated_at: datetime = Field(description="Last update UTC timestamp")
    remarks: Optional[str] = Field(default=None, description="Operational notes")
    shareable_link: Optional[str] = Field(
        default=None, description="Tokenized link for IO review"
    )
    has_parsed_result: bool = Field(
        default=False, description="Whether location result has been extracted"
    )


class LocationExecuteRequest(BaseModel):
    """Schema for IO execution trigger."""

    io_device_id: Optional[str] = Field(
        default=None,
        description="Device identifier used to dispatch SMS",
    )
    sim_slot_index: Optional[int] = Field(
        default=0,
        ge=0,
        le=3,
        description="SIM card slot index utilized on authorized device",
    )


class LocationResultSubmission(BaseModel):
    """Schema for submitting incoming telecom SMS reply."""

    raw_sms_content: str = Field(
        min_length=1,
        description="Raw body of the telecom carrier SMS response",
    )
    sender_address: Optional[str] = Field(
        default=None,
        description="Carrier originating sender address / shortcode",
    )
    received_at: Optional[datetime] = Field(
        default=None,
        description="Device timestamp when SMS reply was intercepted",
    )
