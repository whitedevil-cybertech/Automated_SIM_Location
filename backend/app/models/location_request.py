"""Location Request Document Model for MongoDB.

Defines the structure, nested subdocuments, and forensic metadata for
the 'location_requests' collection.
"""

from datetime import datetime, timezone
import hashlib
from typing import Any, Dict, Optional
from pydantic import BaseModel, Field

from backend.app.core.field_crypto import decrypt_phone_number, encrypt_phone_number
from backend.app.core.logging import mask_phone_number
from backend.app.models.enums import RequestState


class ShareTokenInfo(BaseModel):
    """Secure, single-use token representation for IO authorization."""

    token_hash: str = Field(description="SHA-256 hash of random opaque token")
    expires_at: datetime = Field(description="Expiration timestamp")
    is_used: bool = Field(default=False, description="Whether token has been redeemed")
    used_at: Optional[datetime] = Field(default=None, description="Redemption timestamp")


class ExecutionInfo(BaseModel):
    """Details concerning IO execution and device-level SMS dispatch."""

    dispatched_at: Optional[datetime] = Field(
        default=None, description="When IO device sent the SMS"
    )
    io_device_id: Optional[str] = Field(
        default=None, description="Identifier of the executing IO device"
    )
    sim_slot_index: Optional[int] = Field(
        default=None, description="SIM slot used on IO device (e.g. 0, 1)"
    )
    attempt_count: int = Field(default=0, description="Number of transmission attempts")
    delivery_status: Optional[str] = Field(
        default=None, description="Delivery receipt or intent status"
    )
    last_error: Optional[str] = Field(
        default=None, description="Error message if SMS transmission failed"
    )


class ResponseInfo(BaseModel):
    """Preserved raw SMS response data for forensic chain-of-custody."""

    raw_sms_content: Optional[str] = Field(
        default=None,
        description="Preserved raw SMS body (sensitive field; masked in display/logs)",
    )
    sender_address: Optional[str] = Field(
        default=None, description="Originating carrier shortcode/address"
    )
    received_at: Optional[datetime] = Field(
        default=None, description="When IO device intercepted the SMS reply"
    )
    raw_hash_sha256: Optional[str] = Field(
        default=None, description="SHA-256 hash of raw SMS for integrity verification"
    )


class ParsedLocationResult(BaseModel):
    """Structured location parsed from raw telecom response."""

    latitude: Optional[float] = Field(
        default=None, description="Geographic latitude coordinate"
    )
    longitude: Optional[float] = Field(
        default=None, description="Geographic longitude coordinate"
    )
    accuracy_meters: Optional[float] = Field(
        default=None, description="Accuracy radius in meters if provided by carrier"
    )
    address_text: Optional[str] = Field(
        default=None, description="Human-readable address or cell tower identifier"
    )
    parsed_at: Optional[datetime] = Field(
        default=None, description="Timestamp of parser extraction"
    )
    parser_version: str = Field(
        default="1.0.0", description="Parser logic version tag"
    )


class LocationRequestDocument(BaseModel):
    """MongoDB Document Model for the 'location_requests' collection."""

    request_id: str = Field(description="Unique opaque ID, e.g. REQ-2026-XXXXX")
    case_id: str = Field(description="Case reference / FIR number")
    target_phone_encrypted: str = Field(
        description="Encrypted normalized target number for authorized backend use."
    )
    target_phone_masked: str = Field(
        description="Pre-masked number for UI display (e.g., +91 XXXXXXX210)"
    )
    target_phone_hash: str = Field(
        description="SHA-256 hash of normalized phone number for non-reversible lookup"
    )
    operator_code: str = Field(
        description="Telecom operator identifier code, e.g. JIO, AIRTEL, VI, BSNL"
    )
    submitting_officer_id: str = Field(
        description="Identifier of officer who generated the request"
    )
    executing_io_id: Optional[str] = Field(
        default=None, description="Identifier of the IO assigned to / executing request"
    )
    status: RequestState = Field(
        default=RequestState.CREATED, description="Current lifecycle state"
    )
    created_at: datetime = Field(
        default_factory=lambda: datetime.now(timezone.utc),
        description="Creation timestamp",
    )
    updated_at: datetime = Field(
        default_factory=lambda: datetime.now(timezone.utc),
        description="Last update timestamp",
    )
    remarks: Optional[str] = Field(
        default=None, description="Officer notes / operational remarks"
    )
    metadata: Dict[str, Any] = Field(
        default_factory=dict, description="Extensible operational metadata"
    )
    share_token: Optional[ShareTokenInfo] = Field(
        default=None, description="Tokenized link details for IO access"
    )
    execution_info: ExecutionInfo = Field(
        default_factory=ExecutionInfo, description="Execution and SMS dispatch record"
    )
    response_info: ResponseInfo = Field(
        default_factory=ResponseInfo, description="Forensic SMS response record"
    )
    parsed_result: Optional[ParsedLocationResult] = Field(
        default=None, description="Extracted location data"
    )

    @classmethod
    def create_new(
        cls,
        request_id: str,
        case_id: str,
        target_phone_number: str,
        operator_code: str,
        submitting_officer_id: str,
        remarks: Optional[str] = None,
        share_token: Optional[ShareTokenInfo] = None,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> "LocationRequestDocument":
        """Factory constructor ensuring masking, hashing, and encryption."""
        normalized_phone = target_phone_number.strip()
        masked = mask_phone_number(normalized_phone)
        hashed = hashlib.sha256(normalized_phone.encode("utf-8")).hexdigest()
        now = datetime.now(timezone.utc)

        return cls(
            request_id=request_id,
            case_id=case_id,
            target_phone_encrypted=encrypt_phone_number(normalized_phone),
            target_phone_masked=masked,
            target_phone_hash=hashed,
            operator_code=operator_code.upper().strip(),
            submitting_officer_id=submitting_officer_id.strip(),
            status=RequestState.CREATED,
            created_at=now,
            updated_at=now,
            remarks=remarks,
            share_token=share_token,
            metadata=metadata or {},
        )

    def decrypt_target_phone_number(self) -> str:
        """Recover the normalized target number for authorized backend workflows."""
        return decrypt_phone_number(self.target_phone_encrypted)
