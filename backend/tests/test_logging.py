"""Logging and Redaction Security Tests."""

import json
import logging
from backend.app.core.logging import (
    RedactingJsonFormatter,
    mask_phone_number,
    redact_sensitive_data,
)


def test_mask_phone_number():
    """Verify phone masking preserves only prefix and last 4 digits."""
    assert mask_phone_number("+919876543210") == "+91 XXXXXX3210"
    assert mask_phone_number("9876543210") == "XXXXXX3210"


def test_redact_sensitive_data():
    """Verify redaction filter catches credentials, coordinates, and phone numbers."""
    # Test phone redaction
    log_msg = "Dispatched SMS query for subscriber +919876543210 to carrier"
    redacted = redact_sensitive_data(log_msg)
    assert "+919876543210" not in redacted
    assert "XXXXXX3210" in redacted

    # Test coordinate redaction
    coord_msg = "Carrier reported LAT: 28.6139, LONG: 77.2090 for target"
    redacted_coords = redact_sensitive_data(coord_msg)
    assert "28.6139" not in redacted_coords
    assert "77.2090" not in redacted_coords
    assert "[REDACTED_COORD]" in redacted_coords

    # Test secret / password redaction
    secret_msg = 'Database auth string password="secret_db_password_123"'
    redacted_secret = redact_sensitive_data(secret_msg)
    assert "secret_db_password_123" not in redacted_secret
    assert "[REDACTED_SECRET]" in redacted_secret


def test_json_formatter_outputs_valid_json():
    """Verify RedactingJsonFormatter formats records into valid JSON with redacted text."""
    formatter = RedactingJsonFormatter()
    record = logging.LogRecord(
        name="test_logger",
        level=logging.INFO,
        pathname="test_logging.py",
        lineno=42,
        msg="Target +919876543210 status changed",
        args=(),
        exc_info=None,
    )
    formatted = formatter.format(record)
    parsed = json.loads(formatted)
    assert parsed["level"] == "INFO"
    assert parsed["logger"] == "test_logger"
    assert "+919876543210" not in parsed["message"]
    assert "XXXXXX3210" in parsed["message"]
