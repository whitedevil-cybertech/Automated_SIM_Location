"""Phase 3 Integration & Unit Tests for IO Execution, SMS Dispatch, and Response Ingestion."""

import hashlib
import pytest
from httpx import ASGITransport, AsyncClient

from backend.app.main import app
from backend.app.core.field_crypto import decrypt_sensitive_text
from backend.app.models.location_request import LocationRequestDocument
from backend.tests.conftest import fetch_all_documents
from backend.tests.test_requests_phase2 import (
    ADMIN_AUTH,
    IO_AUTH,
    OFFICER_AUTH,
    _create_pending_request,
)



@pytest.mark.asyncio
async def test_execute_request_returns_dispatch_instructions(
    async_client: AsyncClient, postgres_database
):
    request_id = await _create_pending_request(async_client, postgres_database)

    execute_response = await async_client.post(
        f"/api/v1/requests/{request_id}/execute",
        json={"io_device_id": "MDM-IO-001", "sim_slot_index": 0},
        headers=IO_AUTH,
    )
    assert execute_response.status_code == 200
    payload = execute_response.json()
    assert payload["success"] is True
    assert payload["data"]["status"] == "EXECUTING"
    assert "dispatch_instructions" in payload["data"]

    instructions = payload["data"]["dispatch_instructions"]
    assert instructions["service_number"] == "TEST-SERVICE-NUMBER"
    assert instructions["operator_code"] == "JIO"
    assert instructions["sim_slot_index"] == 0
    assert instructions["sms_body"] == "TEST-COMMAND +919876543210"


@pytest.mark.asyncio
async def test_record_send_status_success_transitions_to_waiting_response(
    async_client: AsyncClient, postgres_database
):
    request_id = await _create_pending_request(async_client, postgres_database)

    # First execute
    await async_client.post(
        f"/api/v1/requests/{request_id}/execute",
        json={"io_device_id": "MDM-IO-001", "sim_slot_index": 0},
        headers=IO_AUTH,
    )

    # Report send success
    send_response = await async_client.post(
        f"/api/v1/requests/{request_id}/send-status",
        json={"success": True, "delivery_status": "SENT"},
        headers=IO_AUTH,
    )
    assert send_response.status_code == 200
    payload = send_response.json()
    assert payload["success"] is True
    assert payload["data"]["status"] == "WAITING_RESPONSE"

    stored = await postgres_database.location_requests.find_one(
        {"request_id": request_id}
    )
    assert stored["status"] == "WAITING_RESPONSE"
    assert stored["execution_info"]["delivery_status"] == "SENT"
    assert stored["execution_info"]["attempt_count"] == 1

    assert any(
        audit["event_type"] == "SMS_DISPATCHED"
        and audit["request_id"] == request_id
        and audit["actor_id"] == "IO-DEV-001"
        for audit in await fetch_all_documents(postgres_database.audit_logs)
    )


@pytest.mark.asyncio
async def test_record_send_status_failure_transitions_to_sms_failed(
    async_client: AsyncClient, postgres_database
):
    request_id = await _create_pending_request(async_client, postgres_database)

    # Execute
    await async_client.post(
        f"/api/v1/requests/{request_id}/execute",
        json={"io_device_id": "MDM-IO-001", "sim_slot_index": 0},
        headers=IO_AUTH,
    )

    # Report send failure
    send_response = await async_client.post(
        f"/api/v1/requests/{request_id}/send-status",
        json={
            "success": False,
            "error_message": "Radio off: No cellular coverage",
        },
        headers=IO_AUTH,
    )
    assert send_response.status_code == 200
    payload = send_response.json()
    assert payload["success"] is True
    assert payload["data"]["status"] == "SMS_FAILED"

    stored = await postgres_database.location_requests.find_one(
        {"request_id": request_id}
    )
    assert stored["status"] == "SMS_FAILED"
    assert stored["execution_info"]["last_error"] == "Radio off: No cellular coverage"
    assert stored["execution_info"]["attempt_count"] == 1

    assert any(
        audit["event_type"] == "SMS_FAILED"
        and audit["request_id"] == request_id
        and audit["actor_id"] == "IO-DEV-001"
        for audit in await fetch_all_documents(postgres_database.audit_logs)
    )


@pytest.mark.asyncio
async def test_record_send_status_rejects_non_executing_state(
    async_client: AsyncClient, postgres_database
):
    request_id = await _create_pending_request(async_client, postgres_database)

    # Try to report send status while still in PENDING_IO_REVIEW
    send_response = await async_client.post(
        f"/api/v1/requests/{request_id}/send-status",
        json={"success": True, "delivery_status": "SENT"},
        headers=IO_AUTH,
    )
    assert send_response.status_code == 409
    assert send_response.json()["error"]["code"] == "INVALID_STATE_TRANSITION"


@pytest.mark.asyncio
async def test_submit_result_success_preserves_raw_sms_and_completes(
    async_client: AsyncClient, postgres_database
):
    request_id = await _create_pending_request(async_client, postgres_database)

    # Execute
    await async_client.post(
        f"/api/v1/requests/{request_id}/execute",
        json={"io_device_id": "MDM-IO-001", "sim_slot_index": 0},
        headers=IO_AUTH,
    )

    # Report SMS sent
    await async_client.post(
        f"/api/v1/requests/{request_id}/send-status",
        json={"success": True, "delivery_status": "SENT"},
        headers=IO_AUTH,
    )

    # Raw incoming telecom response
    raw_telecom_sms = "Location: LAT:28.6139, LONG:77.2090, ACC:50m, TOWER:DL-DEL-041"
    expected_hash = hashlib.sha256(raw_telecom_sms.encode("utf-8")).hexdigest()

    result_response = await async_client.post(
        f"/api/v1/requests/{request_id}/result",
        json={
            "raw_sms_content": raw_telecom_sms,
            "sender_address": "TEST-RESPONSE-SENDER",
        },
        headers=IO_AUTH,
    )
    assert result_response.status_code == 200
    payload = result_response.json()
    assert payload["success"] is True
    assert payload["data"]["status"] == "COMPLETED"
    assert payload["data"]["raw_hash_sha256"] == expected_hash

    stored = await postgres_database.location_requests.find_one(
        {"request_id": request_id}
    )
    assert stored["status"] == "COMPLETED"
    encrypted_raw = stored["response_info"]["raw_sms_content_encrypted"]
    assert encrypted_raw and encrypted_raw != raw_telecom_sms
    assert stored["response_info"]["raw_sms_content"] is None
    assert decrypt_sensitive_text(encrypted_raw) == raw_telecom_sms
    assert stored["response_info"]["raw_hash_sha256"] == expected_hash
    assert stored["response_info"]["sender_address"] == "TEST-RESPONSE-SENDER"

    # Audit log verification: raw content is NOT in audit logs, but hash and sender are
    assert any(
        audit["event_type"] == "SMS_RESPONSE_RECEIVED"
        and audit["request_id"] == request_id
        and audit["details"]["raw_hash_sha256"] == expected_hash
        and audit["details"]["sender_address"] == "TEST-RESPONSE-SENDER"
        for audit in await fetch_all_documents(postgres_database.audit_logs)
    )
    assert any(
        audit["event_type"] == "REQUEST_COMPLETED"
        and audit["request_id"] == request_id
        for audit in await fetch_all_documents(postgres_database.audit_logs)
    )


@pytest.mark.asyncio
async def test_phase3_role_authorization(
    async_client: AsyncClient, postgres_database
):
    request_id = await _create_pending_request(async_client, postgres_database)

    # OFFICER forbidden from send-status
    officer_send = await async_client.post(
        f"/api/v1/requests/{request_id}/send-status",
        json={"success": True},
        headers=OFFICER_AUTH,
    )
    assert officer_send.status_code == 403

    # Unauthenticated rejected from send-status
    unauth_send = await async_client.post(
        f"/api/v1/requests/{request_id}/send-status",
        json={"success": True},
    )
    assert unauth_send.status_code == 401

    # OFFICER forbidden from result submission
    officer_result = await async_client.post(
        f"/api/v1/requests/{request_id}/result",
        json={"raw_sms_content": "test"},
        headers=OFFICER_AUTH,
    )
    assert officer_result.status_code == 403

    # Unauthenticated rejected from result submission
    unauth_result = await async_client.post(
        f"/api/v1/requests/{request_id}/result",
        json={"raw_sms_content": "test"},
    )
    assert unauth_result.status_code == 401