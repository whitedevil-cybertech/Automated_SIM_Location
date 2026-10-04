"""Phase 2 request management API tests."""

from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from typing import Any, Dict
import copy
import re
import pytest

from backend.app.core.database import db_manager
from backend.app.models.location_request import LocationRequestDocument


OFFICER_AUTH = {"Authorization": "Bearer dev-officer-token"}
IO_AUTH = {"Authorization": "Bearer dev-io-token"}
ADMIN_AUTH = {"Authorization": "Bearer dev-admin-token"}


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
        headers={**OFFICER_AUTH, "x-officer-id": "OFFICER-77"},
    )
    assert response.status_code == 201
    payload = response.json()
    assert payload["success"] is True
    data = payload["data"]
    assert data["request_id"].startswith("REQ-")
    assert data["operator_code"] == "JIO"
    assert data["submitting_officer_id"] == "OFFICER-DEV-001"
    assert data["target_phone_masked"].endswith("3210")
    assert "+919876543210" not in str(data)
    assert data["shareable_link"] is None

    stored = fake_database.location_requests.documents[0]
    assert "target_phone_number" not in stored
    assert stored["target_phone_encrypted"] != "+919876543210"
    assert "+919876543210" not in str(stored)
    stored_document = LocationRequestDocument.model_validate(stored)
    assert stored_document.decrypt_target_phone_number() == "+919876543210"
    assert stored["status"] == "CREATED"
    assert stored["share_token"] is None
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
        headers=OFFICER_AUTH,
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
        headers=OFFICER_AUTH,
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
        headers=OFFICER_AUTH,
    )
    request_id = create_response.json()["data"]["request_id"]

    fetch_response = await async_client.get(
        f"/api/v1/requests/{request_id}", headers=OFFICER_AUTH
    )
    assert fetch_response.status_code == 200
    fetched = fetch_response.json()["data"]
    assert fetched["request_id"] == request_id
    assert fetched["shareable_link"] is None
    assert fetched["target_phone_masked"].endswith("3210")

    unknown = await async_client.get(
        "/api/v1/requests/REQ-DOES-NOT-EXIST", headers=OFFICER_AUTH
    )
    assert unknown.status_code == 404
    assert unknown.json()["error"]["code"] == "RESOURCE_NOT_FOUND"


@pytest.mark.asyncio
async def test_authentication_required_invalid_token_and_no_fallback(
    async_client, fake_database: FakeDatabase
):
    await fake_database.operators.insert_one({"operator_code": "JIO", "is_active": True})
    payload = {
        "case_id": "FIR-2026-AUTH-1",
        "target_phone_number": "9876543210",
        "operator_code": "JIO",
    }

    unauthenticated = await async_client.post("/api/v1/requests", json=payload)
    assert unauthenticated.status_code == 401

    invalid = await async_client.post(
        "/api/v1/requests",
        json=payload,
        headers={"Authorization": "Bearer definitely-not-valid"},
    )
    assert invalid.status_code == 401

    spoofed_header_only = await async_client.post(
        "/api/v1/requests",
        json=payload,
        headers={"x-officer-id": "OFFICER-SPOOF"},
    )
    assert spoofed_header_only.status_code == 401
    assert fake_database.location_requests.documents == []


@pytest.mark.asyncio
async def test_get_request_enforces_ownership_and_privileged_access(
    async_client, fake_database: FakeDatabase
):
    own_document = LocationRequestDocument.create_new(
        request_id="REQ-OWNED",
        case_id="CASE-OWNED",
        target_phone_number="+919876543210",
        operator_code="JIO",
        submitting_officer_id="OFFICER-DEV-001",
    )
    other_document = LocationRequestDocument.create_new(
        request_id="REQ-OTHER",
        case_id="CASE-OTHER",
        target_phone_number="+919876543211",
        operator_code="JIO",
        submitting_officer_id="OFFICER-OTHER",
    )
    await fake_database.location_requests.insert_one(own_document.model_dump(mode="json"))
    await fake_database.location_requests.insert_one(other_document.model_dump(mode="json"))

    own = await async_client.get("/api/v1/requests/REQ-OWNED", headers=OFFICER_AUTH)
    assert own.status_code == 200

    unauthorized = await async_client.get("/api/v1/requests/REQ-OTHER", headers=OFFICER_AUTH)
    assert unauthorized.status_code == 404
    assert "CASE-OTHER" not in str(unauthorized.json())
    assert "+919876543211" not in str(unauthorized.json())

    privileged = await async_client.get("/api/v1/requests/REQ-OTHER", headers=IO_AUTH)
    assert privileged.status_code == 200
    assert privileged.json()["data"]["request_id"] == "REQ-OTHER"


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
        headers=OFFICER_AUTH,
    )
    request_id = create_response.json()["data"]["request_id"]
    mint_response = await async_client.post(
        f"/api/v1/requests/{request_id}/share-link",
        headers={**OFFICER_AUTH, "x-officer-id": "OFFICER-SPOOF"},
    )
    assert mint_response.status_code == 200
    shareable_link = mint_response.json()["data"]["shareable_link"]
    token = shareable_link.rsplit("/", 1)[-1]
    assert re.match(r"^[A-Za-z0-9\-_]+$", token)
    assert len(token) >= 32
    assert "FIR-2026-REQ-5" not in shareable_link
    assert "9876543210" not in shareable_link
    assert request_id not in shareable_link
    stored_share_token = fake_database.location_requests.documents[0]["share_token"]
    assert "token_hash" in stored_share_token
    assert stored_share_token["token_hash"] != token
    assert "token" not in stored_share_token

    first_access = await async_client.get(
        f"/api/v1/request-links/{token}",
        headers={**IO_AUTH, "x-actor-id": "IO-SPOOF"},
    )
    assert first_access.status_code == 200
    assert first_access.json()["data"]["shareable_link"] is None
    assert any(
        audit["event_type"] == "SHAREABLE_LINK_ACCESSED"
        and audit["actor_id"] == "IO-DEV-001"
        for audit in fake_database.audit_logs.documents
    )

    replay = await async_client.get(f"/api/v1/request-links/{token}", headers=IO_AUTH)
    assert replay.status_code == 404
    assert replay.json()["error"]["code"] == "RESOURCE_NOT_FOUND"

    invalid = await async_client.get(
        "/api/v1/request-links/invalidtokeninvalidtokeninvalidtoken",
        headers=IO_AUTH,
    )
    assert invalid.status_code == 404

    create_response_expired = await async_client.post(
        "/api/v1/requests",
        json={
            "case_id": "FIR-2026-REQ-6",
            "target_phone_number": "9876543210",
            "operator_code": "BSNL",
        },
        headers=OFFICER_AUTH,
    )
    expired_request_id = create_response_expired.json()["data"]["request_id"]
    expired_link_response = await async_client.post(
        f"/api/v1/requests/{expired_request_id}/share-link",
        headers=OFFICER_AUTH,
    )
    expired_token = expired_link_response.json()["data"]["shareable_link"].rsplit("/", 1)[-1]
    fake_database.location_requests.documents[-1]["share_token"]["expires_at"] = datetime.now(
        timezone.utc
    ) - timedelta(hours=1)
    expired_access = await async_client.get(
        f"/api/v1/request-links/{expired_token}", headers=IO_AUTH
    )
    assert expired_access.status_code == 404


@pytest.mark.asyncio
async def test_share_link_requires_io_auth(async_client, fake_database: FakeDatabase):
    await fake_database.operators.insert_one({"operator_code": "BSNL", "is_active": True})
    create_response = await async_client.post(
        "/api/v1/requests",
        json={
            "case_id": "FIR-2026-REQ-7",
            "target_phone_number": "9876543210",
            "operator_code": "BSNL",
        },
        headers=OFFICER_AUTH,
    )
    request_id = create_response.json()["data"]["request_id"]
    link_response = await async_client.post(
        f"/api/v1/requests/{request_id}/share-link",
        headers=OFFICER_AUTH,
    )
    token = link_response.json()["data"]["shareable_link"].rsplit("/", 1)[-1]

    no_auth = await async_client.get(f"/api/v1/request-links/{token}")
    assert no_auth.status_code == 401

    officer_auth = await async_client.get(
        f"/api/v1/request-links/{token}", headers=OFFICER_AUTH
    )
    assert officer_auth.status_code == 403
