"""Tests for the Phase 3 IO pending-requests endpoint."""

from datetime import datetime, timedelta, timezone

import pytest

from backend.app.models.enums import RequestState
from backend.app.models.location_request import LocationRequestDocument


# Development/testing authentication tokens configured by the application.
IO_AUTH = {"Authorization": "Bearer test-io-token"}
OFFICER_AUTH = {"Authorization": "Bearer test-officer-token"}


def _make_request_document(
    *,
    request_id: str,
    status: RequestState,
    created_at: datetime,
) -> dict:
    """Create a valid persisted request document for endpoint tests."""
    document = LocationRequestDocument.create_new(
        request_id=request_id,
        case_id=f"CASE-{request_id}",
        target_phone_number="+919876543210",
        operator_code="JIO",
        submitting_officer_id="OFFICER-DEV-001",
    ).model_dump(mode="json")

    document["status"] = status.value
    document["created_at"] = created_at.isoformat()
    document["updated_at"] = created_at.isoformat()

    return document


@pytest.mark.asyncio
async def test_io_can_retrieve_pending_requests(
    async_client,
    postgres_database,
):
    """An authenticated IO can retrieve requests awaiting review."""
    now = datetime.now(timezone.utc)

    pending_request = _make_request_document(
        request_id="REQ-PENDING-001",
        status=RequestState.PENDING_IO_REVIEW,
        created_at=now,
    )

    await postgres_database.location_requests.insert_one(pending_request)

    response = await async_client.get(
        "/api/v1/requests/io/pending",
        headers=IO_AUTH,
    )

    assert response.status_code == 200

    payload = response.json()

    assert payload["success"] is True
    assert isinstance(payload["data"], list)
    assert len(payload["data"]) == 1
    assert payload["data"][0]["request_id"] == "REQ-PENDING-001"
    assert payload["data"][0]["status"] == "PENDING_IO_REVIEW"


@pytest.mark.asyncio
async def test_pending_queue_excludes_requests_in_other_states(
    async_client,
    postgres_database,
):
    """Only PENDING_IO_REVIEW requests should appear in the IO queue."""
    now = datetime.now(timezone.utc)

    pending_request = _make_request_document(
        request_id="REQ-PENDING-002",
        status=RequestState.PENDING_IO_REVIEW,
        created_at=now,
    )

    created_request = _make_request_document(
        request_id="REQ-CREATED-001",
        status=RequestState.CREATED,
        created_at=now - timedelta(minutes=1),
    )

    executing_request = _make_request_document(
        request_id="REQ-EXECUTING-001",
        status=RequestState.EXECUTING,
        created_at=now - timedelta(minutes=2),
    )

    await postgres_database.location_requests.insert_one(pending_request)
    await postgres_database.location_requests.insert_one(created_request)
    await postgres_database.location_requests.insert_one(executing_request)

    response = await async_client.get(
        "/api/v1/requests/io/pending",
        headers=IO_AUTH,
    )

    assert response.status_code == 200

    payload = response.json()

    assert payload["success"] is True

    returned_ids = [
        item["request_id"]
        for item in payload["data"]
    ]

    assert returned_ids == ["REQ-PENDING-002"]


@pytest.mark.asyncio
async def test_pending_requests_are_ordered_newest_first(
    async_client,
    postgres_database,
):
    """The newest pending request should appear first."""
    now = datetime.now(timezone.utc)

    older_request = _make_request_document(
        request_id="REQ-OLDER-001",
        status=RequestState.PENDING_IO_REVIEW,
        created_at=now - timedelta(hours=2),
    )

    newer_request = _make_request_document(
        request_id="REQ-NEWER-001",
        status=RequestState.PENDING_IO_REVIEW,
        created_at=now - timedelta(minutes=5),
    )

    newest_request = _make_request_document(
        request_id="REQ-NEWEST-001",
        status=RequestState.PENDING_IO_REVIEW,
        created_at=now,
    )

    # Insert them in a different order to verify database sorting.
    await postgres_database.location_requests.insert_one(older_request)
    await postgres_database.location_requests.insert_one(newest_request)
    await postgres_database.location_requests.insert_one(newer_request)

    response = await async_client.get(
        "/api/v1/requests/io/pending",
        headers=IO_AUTH,
    )

    assert response.status_code == 200

    returned_ids = [
        item["request_id"]
        for item in response.json()["data"]
    ]

    assert returned_ids == [
        "REQ-NEWEST-001",
        "REQ-NEWER-001",
        "REQ-OLDER-001",
    ]


@pytest.mark.asyncio
async def test_officer_cannot_access_pending_io_queue(
    async_client,
    postgres_database,
):
    """An officer must not access the IO-only pending queue."""
    response = await async_client.get(
        "/api/v1/requests/io/pending",
        headers=OFFICER_AUTH,
    )

    assert response.status_code == 403


@pytest.mark.asyncio
async def test_pending_queue_returns_empty_list_when_no_requests_exist(
    async_client,
    postgres_database,
):
    """An empty queue should return HTTP 200 and an empty data list."""
    response = await async_client.get(
        "/api/v1/requests/io/pending",
        headers=IO_AUTH,
    )

    assert response.status_code == 200

    payload = response.json()

    assert payload["success"] is True
    assert payload["data"] == []