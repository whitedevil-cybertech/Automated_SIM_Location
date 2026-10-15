"""Bounded request-timeout transitions backed by PostgreSQL JSONB payloads."""
from __future__ import annotations

import asyncio
from datetime import datetime, timedelta, timezone
from typing import Any

from backend.app.core.config import get_settings
from backend.app.core.database import db_manager
from backend.app.models.audit_log import AuditLogDocument
from backend.app.models.enums import AuditEventType, RequestState, UserRole

SYSTEM_ACTOR_ID = "SYSTEM:REQUEST_TIMEOUT_WORKER"


def _as_utc_datetime(value: Any) -> datetime | None:
    if isinstance(value, datetime):
        dt = value
    elif isinstance(value, str):
        try:
            dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            return None
    else:
        return None
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


async def expire_timed_out_requests(now: datetime | None = None) -> int:
    """Transition overdue WAITING_RESPONSE requests to TIMEOUT once, with audit.

    Returns the number of successful transitions. It never retries or sends SMS.
    """
    if not db_manager.is_connected:
        return 0
    cfg = get_settings()
    instant = now or datetime.now(timezone.utc)
    cutoff = instant - timedelta(minutes=cfg.sms_timeout_minutes)
    expired = 0
    async for data in db_manager.location_requests.find({"status": RequestState.WAITING_RESPONSE.value}):
        request_id = data.get("request_id")
        execution = data.get("execution_info") or {}
        started = _as_utc_datetime(execution.get("awaiting_response_since"))
        if not request_id or started is None or started > cutoff:
            continue
        result = await db_manager.location_requests.update_one(
            {"request_id": request_id, "status": RequestState.WAITING_RESPONSE.value},
            {"$set": {"status": RequestState.TIMEOUT.value, "updated_at": instant}},
        )
        if result.modified_count != 1:
            continue
        audit = AuditLogDocument(
            request_id=request_id,
            actor_id=SYSTEM_ACTOR_ID,
            actor_role=UserRole.SYSTEM,
            event_type=AuditEventType.REQUEST_TIMEOUT,
            details={
                "previous_status": RequestState.WAITING_RESPONSE.value,
                "status": RequestState.TIMEOUT.value,
                "awaiting_response_since": started.isoformat(),
                "timeout_minutes": cfg.sms_timeout_minutes,
                "timeout_detected_at": instant.isoformat(),
            },
        )
        await db_manager.audit_logs.insert_one(audit.model_dump(mode="json"))
        expired += 1
    return expired


async def timeout_worker(stop_event: asyncio.Event) -> None:
    """Poll for expired responses until application shutdown."""
    while not stop_event.is_set():
        try:
            await expire_timed_out_requests()
        except Exception:
            # Do not terminate the worker on a transient DB error. Application
            # structured logs avoid embedding request target or raw SMS content.
            from backend.app.core.logging import get_logger
            get_logger(__name__).exception("Request timeout worker iteration failed")
        try:
            await asyncio.wait_for(stop_event.wait(), timeout=get_settings().timeout_worker_interval_seconds)
        except asyncio.TimeoutError:
            pass
