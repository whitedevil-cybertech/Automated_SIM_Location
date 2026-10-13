"""Regression tests for secure request-link access and IO review transitions."""

import hashlib
from datetime import datetime, timedelta, timezone

import pytest

from backend.app.models.audit_log import AuditLogDocument
from backend.app.models.enums import AuditEventType, RequestState
from backend.app.models.location_request import (
    LocationRequestDocument,
    ShareTokenInfo,
)

IO_AUTH = {"Authorization": "Bearer dev-io-token"}

VALID_TOKEN = "test-share-token-12345678901234567890"


def create_request(
    *,
    request_id: str = "REQ-LINK-001",
    status: RequestState = RequestState.CREATED,
    token: str = VALID_TOKEN,
    expires_at: datetime | None = None,
) -> LocationRequestDocument:
    """Create a request with a valid or expired share token."""
    if expires_at is None:
        expires_at = datetime.now(timezone.utc) + timedelta(minutes=15)

    share_token = ShareTokenInfo(
        token_hash=hashlib.sha256(token.encode("utf-8")).hexdigest(),
        expires_at=expires_at,
        is_used=False,
    )

    request = LocationRequestDocument.create_new(
        request_id=request_id,
        case_id="CASE-LINK-001",
        target_phone_number="9876543210",
        operator_code="JIO",
        submitting_officer_id="officer-001",
        share_token=share_token,
    )

    request.status = status
    return request


def seed_request(fake_database, request: LocationRequestDocument) -> None:
    """Insert a request into the in-memory test database."""
    fake_database.location_requests.documents.append(
        request.model_dump(mode="json")
    )


def audit_event_types(fake_database) -> list[str]:
    """Return the event types recorded in the audit collection."""
    events = []

    for document in fake_database.audit_logs.documents:
        event_type = document["event_type"]

        if hasattr(event_type, "value"):
            event_type = event_type.value

        events.append(str(event_type))

    return events


@pytest.mark.asyncio
async def test_valid_link_moves_created_request_to_io_review(
    async_client,
    fake_database,
):
    request = create_request()
    seed_request(fake_database, request)

    response = await async_client.get(
        f"/api/v1/request-links/{VALID_TOKEN}",
        headers=IO_AUTH,
    )

    assert response.status_code == 200

    body = response.json()
    assert body["success"] is True
    assert body["data"]["request_id"] == request.request_id
    assert body["data"]["status"] == RequestState.PENDING_IO_REVIEW.value

    stored = await fake_database.location_requests.find_one(
        {"request_id": request.request_id}
    )

    assert stored["status"] == RequestState.PENDING_IO_REVIEW.value
    assert stored["share_token"]["is_used"] is True
    assert stored["share_token"]["used_at"] is not None

    events = audit_event_types(fake_database)

    assert AuditEventType.SHAREABLE_LINK_ACCESSED.value in events
    assert AuditEventType.IO_REVIEW_STARTED.value in events


@pytest.mark.asyncio
async def test_share_link_cannot_be_redeemed_twice(
    async_client,
    fake_database,
):
    request = create_request()
    seed_request(fake_database, request)

    first_response = await async_client.get(
        f"/api/v1/request-links/{VALID_TOKEN}",
        headers=IO_AUTH,
    )

    assert first_response.status_code == 200

    second_response = await async_client.get(
        f"/api/v1/request-links/{VALID_TOKEN}",
        headers=IO_AUTH,
    )

    assert second_response.status_code == 404

    stored = await fake_database.location_requests.find_one(
        {"request_id": request.request_id}
    )

    assert stored["share_token"]["is_used"] is True

    # Only the first redemption should have generated audit events.
    events = audit_event_types(fake_database)

    assert events.count(AuditEventType.SHAREABLE_LINK_ACCESSED.value) == 1
    assert events.count(AuditEventType.IO_REVIEW_STARTED.value) == 1


@pytest.mark.asyncio
async def test_expired_share_link_is_rejected(
    async_client,
    fake_database,
):
    expired_token = "expired-share-token-123456789012"
    request = create_request(
        request_id="REQ-LINK-EXPIRED",
        token=expired_token,
        expires_at=datetime.now(timezone.utc) - timedelta(minutes=5),
    )
    seed_request(fake_database, request)

    response = await async_client.get(
        f"/api/v1/request-links/{expired_token}",
        headers=IO_AUTH,
    )

    assert response.status_code == 404

    stored = await fake_database.location_requests.find_one(
        {"request_id": request.request_id}
    )

    assert stored["status"] == RequestState.CREATED.value
    assert stored["share_token"]["is_used"] is False
    assert fake_database.audit_logs.documents == []


@pytest.mark.asyncio
async def test_invalid_share_token_is_rejected(
    async_client,
    fake_database,
):
    request = create_request()
    seed_request(fake_database, request)

    invalid_token = "invalid-share-token-123456789012"

    response = await async_client.get(
        f"/api/v1/request-links/{invalid_token}",
        headers=IO_AUTH,
    )

    assert response.status_code == 404

    stored = await fake_database.location_requests.find_one(
        {"request_id": request.request_id}
    )

    assert stored["status"] == RequestState.CREATED.value
    assert stored["share_token"]["is_used"] is False
    assert fake_database.audit_logs.documents == []


@pytest.mark.asyncio
async def test_accessing_link_does_not_reset_existing_request_state(
    async_client,
    fake_database,
):
    token = "reviewed-share-token-123456789012"
    request = create_request(
        request_id="REQ-LINK-REVIEWED",
        status=RequestState.PENDING_IO_REVIEW,
        token=token,
    )
    seed_request(fake_database, request)

    response = await async_client.get(
        f"/api/v1/request-links/{token}",
        headers=IO_AUTH,
    )

    assert response.status_code == 200
    assert response.json()["data"]["status"] == (
        RequestState.PENDING_IO_REVIEW.value
    )

    stored = await fake_database.location_requests.find_one(
        {"request_id": request.request_id}
    )

    assert stored["status"] == RequestState.PENDING_IO_REVIEW.value
    assert stored["share_token"]["is_used"] is True

    events = audit_event_types(fake_database)

    assert events.count(AuditEventType.SHAREABLE_LINK_ACCESSED.value) == 1
    assert AuditEventType.IO_REVIEW_STARTED.value not in events