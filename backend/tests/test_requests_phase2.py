"""Phase 2 request management API tests."""

from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from typing import Any, Dict
import copy
import re
import pytest

from backend.app.core.database import db_manager


def _get_nested(document: Dict[str, Any], path: str) -> Any:
    current: Any = document
    for part in path.split("."):
        if not isinstance(current, dict) or part not in current:
            return None
        current = current[part]
    return current


def _set_nested(document: Dict[str, Any], path: str, value: Any) -> None:
    current = document
    parts = path.split(".")
    for part in parts[:-1]:
        if part not in current or not isinstance(current[part], dict):
            current[part] = {}
        current = current[part]
    current[parts[-1]] = value


def _matches(document: Dict[str, Any], query: Dict[str, Any]) -> bool:
    for key, expected in query.items():
        if _get_nested(document, key) != expected:
            return False
    return True


class FakeCollection:
    def __init__(self) -> None:
        self.documents: list[Dict[str, Any]] = []

    async def insert_one(self, document: Dict[str, Any]):
        self.documents.append(copy.deepcopy(document))
        return SimpleNamespace(inserted_id=len(self.documents))

    async def find_one(self, query: Dict[str, Any], projection: Dict[str, int] | None = None):
        for document in self.documents:
            if _matches(document, query):
                return copy.deepcopy(document)
        return None

    async def update_one(self, query: Dict[str, Any], update: Dict[str, Any]):
        for document in self.documents:
            if _matches(document, query):
                for key, value in update.get("$set", {}).items():
                    _set_nested(document, key, value)
                return SimpleNamespace(modified_count=1)
        return SimpleNamespace(modified_count=0)


class FakeDatabase:
    def __init__(self) -> None:
        self.location_requests = FakeCollection()
        self.operators = FakeCollection()
        self.audit_logs = FakeCollection()

    def __getitem__(self, name: str):
        return getattr(self, name)


@pytest.fixture
def fake_database(monkeypatch: pytest.MonkeyPatch) -> FakeDatabase:
    fake_db = FakeDatabase()
    monkeypatch.setattr(db_manager, "get_database", lambda: fake_db)
    return fake_db


@pytest.mark.asyncio
async def test_create_request_success_and_persistence(async_client, fake_database: FakeDatabase):
    await fake_database.operators.insert_one({"operator_code": "JIO", "is_active": True})

    response = await async_client.post(
        "/api/v1/requests",
        json={
            "case_id": "FIR-2026-REQ-1",
            "target_phone_number": "9876543210",
            "operator_code": " jio ",
            "remarks": "Urgent follow-up",
        },
        headers={"x-officer-id": "OFFICER-77"},
    )
    assert response.status_code == 201
    payload = response.json()
    assert payload["success"] is True
    data = payload["data"]
    assert data["request_id"].startswith("REQ-")
    assert data["operator_code"] == "JIO"
    assert data["submitting_officer_id"] == "OFFICER-77"
    assert data["target_phone_masked"].endswith("3210")
    assert "+919876543210" not in str(data)
    assert data["shareable_link"].startswith("http://testserver/api/v1/request-links/")
    assert "FIR-2026-REQ-1" not in data["shareable_link"]
    assert "9876543210" not in data["shareable_link"]
    assert data["request_id"] not in data["shareable_link"]

    stored = fake_database.location_requests.documents[0]
    assert stored["target_phone_number"] == "+919876543210"
    assert stored["status"] == "CREATED"
    assert "token_hash" in stored["share_token"]
    assert "token" not in stored["share_token"]
    assert len(fake_database.audit_logs.documents) == 1
    assert fake_database.audit_logs.documents[0]["event_type"] == "REQUEST_CREATED"


@pytest.mark.asyncio
async def test_create_request_invalid_phone(async_client, fake_database: FakeDatabase):
    await fake_database.operators.insert_one({"operator_code": "JIO", "is_active": True})
    response = await async_client.post(
        "/api/v1/requests",
        json={
            "case_id": "FIR-2026-REQ-2",
            "target_phone_number": "12345",
            "operator_code": "JIO",
        },
    )
    assert response.status_code == 422
    payload = response.json()
    assert payload["success"] is False
    assert payload["error"]["code"] == "REQUEST_VALIDATION_FAILED"


@pytest.mark.asyncio
async def test_create_request_rejects_inactive_operator(async_client, fake_database: FakeDatabase):
    await fake_database.operators.insert_one({"operator_code": "VI", "is_active": False})
    response = await async_client.post(
        "/api/v1/requests",
        json={
            "case_id": "FIR-2026-REQ-3",
            "target_phone_number": "9876543210",
            "operator_code": "VI",
        },
    )
    assert response.status_code == 422
    payload = response.json()
    assert payload["success"] is False
    assert payload["error"]["code"] == "VALIDATION_ERROR"


@pytest.mark.asyncio
async def test_get_request_and_404(async_client, fake_database: FakeDatabase):
    await fake_database.operators.insert_one({"operator_code": "AIRTEL", "is_active": True})
    create_response = await async_client.post(
        "/api/v1/requests",
        json={
            "case_id": "FIR-2026-REQ-4",
            "target_phone_number": "9876543210",
            "operator_code": "AIRTEL",
        },
    )
    request_id = create_response.json()["data"]["request_id"]

    fetch_response = await async_client.get(f"/api/v1/requests/{request_id}")
    assert fetch_response.status_code == 200
    fetched = fetch_response.json()["data"]
    assert fetched["request_id"] == request_id
    assert fetched["shareable_link"] is None
    assert fetched["target_phone_masked"].endswith("3210")

    unknown = await async_client.get("/api/v1/requests/REQ-DOES-NOT-EXIST")
    assert unknown.status_code == 404
    assert unknown.json()["error"]["code"] == "RESOURCE_NOT_FOUND"


@pytest.mark.asyncio
async def test_token_access_success_replay_invalid_and_expired(
    async_client, fake_database: FakeDatabase
):
    await fake_database.operators.insert_one({"operator_code": "BSNL", "is_active": True})
    create_response = await async_client.post(
        "/api/v1/requests",
        json={
            "case_id": "FIR-2026-REQ-5",
            "target_phone_number": "9876543210",
            "operator_code": "BSNL",
        },
    )
    shareable_link = create_response.json()["data"]["shareable_link"]
    token = shareable_link.rsplit("/", 1)[-1]
    assert re.match(r"^[A-Za-z0-9\-_]+$", token)

    first_access = await async_client.get(
        f"/api/v1/request-links/{token}", headers={"x-actor-id": "IO-22"}
    )
    assert first_access.status_code == 200
    assert first_access.json()["data"]["shareable_link"] is None
    assert any(
        audit["event_type"] == "SHAREABLE_LINK_ACCESSED"
        for audit in fake_database.audit_logs.documents
    )

    replay = await async_client.get(f"/api/v1/request-links/{token}")
    assert replay.status_code == 404
    assert replay.json()["error"]["code"] == "RESOURCE_NOT_FOUND"

    invalid = await async_client.get(
        "/api/v1/request-links/invalidtokeninvalidtokeninvalidtoken"
    )
    assert invalid.status_code == 404

    create_response_expired = await async_client.post(
        "/api/v1/requests",
        json={
            "case_id": "FIR-2026-REQ-6",
            "target_phone_number": "9876543210",
            "operator_code": "BSNL",
        },
    )
    expired_token = create_response_expired.json()["data"]["shareable_link"].rsplit("/", 1)[-1]
    fake_database.location_requests.documents[-1]["share_token"]["expires_at"] = datetime.now(
        timezone.utc
    ) - timedelta(hours=1)
    expired_access = await async_client.get(f"/api/v1/request-links/{expired_token}")
    assert expired_access.status_code == 404
