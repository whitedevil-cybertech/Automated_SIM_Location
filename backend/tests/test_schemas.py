"""Pydantic Schema and Document Model Validation Tests."""

import hashlib
import pytest
from pydantic import ValidationError

from backend.app.models.enums import RequestState
from backend.app.models.location_request import LocationRequestDocument
from backend.app.schemas.location_request import LocationRequestCreate


def test_location_request_create_valid_10_digit():
    """Verify standard 10-digit number normalizes to +91 country prefix."""
    req = LocationRequestCreate(
        case_id="FIR-2026-TEST-01",
        target_phone_number="9876543210",
        operator_code="jio",
    )
    assert req.target_phone_number == "+919876543210"
    assert req.operator_code == "JIO"
    assert req.case_id == "FIR-2026-TEST-01"


def test_location_request_create_valid_e164():
    """Verify E.164 pre-formatted number is preserved."""
    req = LocationRequestCreate(
        case_id="FIR-2026-TEST-02",
        target_phone_number="+919876543210",
        operator_code="AIRTEL",
    )
    assert req.target_phone_number == "+919876543210"


def test_location_request_create_invalid_phone():
    """Verify malformed phone numbers fail schema validation."""
    with pytest.raises(ValidationError):
        LocationRequestCreate(
            case_id="FIR-2026-TEST-03",
            target_phone_number="12345",  # Too short
            operator_code="VI",
        )

    with pytest.raises(ValidationError):
        LocationRequestCreate(
            case_id="FIR-2026-TEST-04",
            target_phone_number="abcdefghij",  # Non-numeric
            operator_code="VI",
        )


def test_location_request_create_empty_case_id():
    """Verify empty case ID fails validation."""
    with pytest.raises(ValidationError):
        LocationRequestCreate(
            case_id="   ",
            target_phone_number="9876543210",
            operator_code="VI",
        )


def test_location_request_document_creation_and_masking():
    """Verify LocationRequestDocument factory computes hash and masks phone number."""
    phone = "+919876543210"
    doc = LocationRequestDocument.create_new(
        request_id="REQ-TEST-0001",
        case_id="CASE-1234",
        target_phone_number=phone,
        operator_code="JIO",
        submitting_officer_id="OFFICER-42",
        remarks="Test investigation",
    )

    assert doc.request_id == "REQ-TEST-0001"
    assert doc.status == RequestState.CREATED
    assert doc.target_phone_number == phone
    # Verify masked format shows prefix and last 4 digits
    assert doc.target_phone_masked == "+91 XXXXXX3210"
    # Verify SHA-256 hash matches
    expected_hash = hashlib.sha256(phone.encode("utf-8")).hexdigest()
    assert doc.target_phone_hash == expected_hash
    assert doc.created_at is not None
    assert doc.updated_at is not None
