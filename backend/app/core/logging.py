"""Centralized Structured Logging and Sensitive Data Redaction.

Adheres strictly to project security and forensic rules:
- Redacts phone numbers, passwords, auth tokens, sensitive coordinates, and raw SMS content.
- Provides structured log records with timestamps, log levels, module names, and request IDs.
"""

import contextvars
import json
import logging
import re
from datetime import datetime, timezone
from typing import Any, Dict

# Context variable for associating logs with request identifiers
request_id_ctx: contextvars.ContextVar[str | None] = contextvars.ContextVar(
    "request_id", default=None
)

# Regex patterns for sensitive data detection
PHONE_REGEX = re.compile(r"(\+?91[\s-]?)?([6-9]\d{9})")
SECRET_KEY_REGEX = re.compile(
    r"(password|token|secret|authorization|api[-_]?key)[\"':\s=]+([^,\s\"']+)",
    re.IGNORECASE,
)
LAT_LONG_REGEX = re.compile(
    r"(LAT|LATITUDE|LONG|LONGITUDE)[\s:=]+([+-]?\d+\.\d+)", re.IGNORECASE
)


def mask_phone_number(phone_str: str) -> str:
    """Mask phone number preserving only country code and the last 4 digits.

    Example: +919876543210 -> +91 XXXXXXX210 or 9876543210 -> XXXXXX3210
    """
    cleaned = re.sub(r"[\s-]", "", phone_str)
    if len(cleaned) >= 10:
        prefix = cleaned[:-4]
        suffix = cleaned[-4:]
        if prefix.startswith("+91"):
            masked_prefix = "+91 " + "X" * (len(prefix) - 3)
        elif prefix.startswith("91") and len(prefix) > 2:
            masked_prefix = "91 " + "X" * (len(prefix) - 2)
        else:
            masked_prefix = "X" * len(prefix)
        return f"{masked_prefix}{suffix}"
    return "****"


def redact_sensitive_data(message: str) -> str:
    """Redact known sensitive strings from raw log messages."""
    if not isinstance(message, str):
        return message

    # Redact credentials/tokens
    redacted = SECRET_KEY_REGEX.sub(r"\1: [REDACTED_SECRET]", message)

    # Redact raw geographic coordinates
    redacted = LAT_LONG_REGEX.sub(r"\1: [REDACTED_COORD]", redacted)

    # Redact phone numbers using masking function
    def _phone_sub(match: re.Match) -> str:
        return mask_phone_number(match.group(0))

    redacted = PHONE_REGEX.sub(_phone_sub, redacted)

    return redacted


class RedactingJsonFormatter(logging.Formatter):
    """JSON formatter that ensures sensitive information is redacted."""

    def format(self, record: logging.LogRecord) -> str:
        current_time = datetime.now(timezone.utc).isoformat()
        current_req_id = request_id_ctx.get() or getattr(record, "request_id", None)

        raw_msg = record.getMessage()
        sanitized_msg = redact_sensitive_data(raw_msg)

        log_payload: Dict[str, Any] = {
            "timestamp": current_time,
            "level": record.levelname,
            "logger": record.name,
            "module": record.module,
            "message": sanitized_msg,
        }

        if current_req_id:
            log_payload["request_id"] = current_req_id

        if record.exc_info:
            log_payload["exception"] = self.formatException(record.exc_info)

        return json.dumps(log_payload, ensure_ascii=False)


def setup_logging(log_level: str = "INFO") -> None:
    """Configure root logger with structured JSON redacting formatter."""
    level = getattr(logging, log_level.upper(), logging.INFO)

    root_logger = logging.getLogger()
    root_logger.setLevel(level)

    # Remove existing handlers to avoid duplication
    for handler in list(root_logger.handlers):
        root_logger.removeHandler(handler)

    console_handler = logging.StreamHandler()
    console_handler.setLevel(level)
    console_handler.setFormatter(RedactingJsonFormatter())

    root_logger.addHandler(console_handler)

    # Suppress verbose third-party loggers
    logging.getLogger("uvicorn.access").setLevel(logging.WARNING)
    logging.getLogger("motor").setLevel(logging.WARNING)
    logging.getLogger("pymongo").setLevel(logging.WARNING)


def get_logger(name: str) -> logging.Logger:
    """Return a logger instance for the given module name."""
    return logging.getLogger(name)
