"""Focused timeout timestamp parsing tests; no database required."""
from datetime import datetime, timezone

from backend.app.services.request_timeouts import _as_utc_datetime


def test_timeout_timestamp_parses_utc_z_suffix():
    result = _as_utc_datetime("2026-10-14T10:00:00Z")
    assert result == datetime(2026, 10, 14, 10, 0, tzinfo=timezone.utc)


def test_timeout_timestamp_treats_naive_values_as_utc():
    result = _as_utc_datetime("2026-10-14T10:00:00")
    assert result == datetime(2026, 10, 14, 10, 0, tzinfo=timezone.utc)


def test_timeout_timestamp_rejects_invalid_values():
    assert _as_utc_datetime("not-a-timestamp") is None
    assert _as_utc_datetime(None) is None
