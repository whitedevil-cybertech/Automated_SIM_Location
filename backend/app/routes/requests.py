"""Location Request API Routes (Phase 2 Officer Request Management)."""

from datetime import datetime, timedelta, timezone
import hashlib
import secrets
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Path, Request, status

from backend.app.core.auth import (
    AuthenticatedPrincipal,
    can_access_request,
    get_current_principal,
    require_role,
)
from backend.app.core.config import get_settings
from backend.app.core.database import db_manager
from backend.app.core.exceptions import (
    InvalidStateTransitionError,
    ResourceNotFoundError,
    ValidationException,
)
from backend.app.models.audit_log import AuditLogDocument
from backend.app.models.enums import (
    AuditEventType,
    RequestState,
    UserRole,
    is_valid_transition,
)
from backend.app.models.location_request import (
    LocationRequestDocument,
    ResponseInfo,
    ShareTokenInfo,
)
from backend.app.routes.operators import DEMO_OPERATORS
from backend.app.schemas.common import ApiResponse
from backend.app.schemas.location_request import (
    DispatchInstructions,
    LocationExecuteRequest,
    LocationRequestCreate,
    LocationRequestResponse,
    LocationResultSubmission,
    LocationSendStatusUpdate,
)

router = APIRouter(prefix="/requests", tags=["Location Requests"])


def _build_shareable_link(request: Request, raw_token: str) -> str:
    return str(request.url_for("access_request_link", token=raw_token))


def _to_response(
    document: LocationRequestDocument, *, shareable_link: Optional[str] = None
) -> LocationRequestResponse:
    return LocationRequestResponse(
        request_id=document.request_id,
        case_id=document.case_id,
        target_phone_masked=document.target_phone_masked,
        operator_code=document.operator_code,
        submitting_officer_id=document.submitting_officer_id,
        executing_io_id=document.executing_io_id,
        status=document.status,
        created_at=document.created_at,
        updated_at=document.updated_at,
        remarks=document.remarks,
        shareable_link=shareable_link,
        has_parsed_result=document.parsed_result is not None,
    )


async def _is_operator_active(operator_code: str) -> bool:
    db_operator = await db_manager.operators.find_one({"operator_code": operator_code})
    if db_operator is not None:
        return bool(db_operator.get("is_active", False))

    return any(
        op.operator_code == operator_code and op.is_active for op in DEMO_OPERATORS
    )


# Approved development/test carrier dispatch profiles (Rules.md / PRD.md)
DEFAULT_OPERATOR_CONFIGS = {
    "JIO": {"service_number": "1512", "sms_template": "LOC {number}"},
    "AIRTEL": {"service_number": "1513", "sms_template": "LOC {number}"},
    "VI": {"service_number": "1514", "sms_template": "LOC {number}"},
    "BSNL": {"service_number": "1515", "sms_template": "LOC {number}"},
}


def _format_sms_template(template: str, normalized_phone: str) -> str:
    """Format approved operator SMS template without exposing unapproved patterns."""
    if "{number}" in template:
        return template.format(number=normalized_phone)
    if "{normalized_number}" in template:
        return template.format(normalized_number=normalized_phone)
    if "%s" in template:
        return template % normalized_phone
    return f"{template} {normalized_phone}".strip()


async def _get_operator_dispatch_config(operator_code: str) -> dict:
    """Retrieve approved carrier dispatch configuration from database or approved fallback."""
    db_operator = await db_manager.operators.find_one({"operator_code": operator_code})
    service_number = None
    sms_template = None
    if db_operator is not None:
        service_number = db_operator.get("service_number")
        sms_template = db_operator.get("sms_template")

    fallback = DEFAULT_OPERATOR_CONFIGS.get(
        operator_code,
        {"service_number": "1512", "sms_template": "LOC {number}"},
    )
    return {
        "service_number": service_number or fallback["service_number"],
        "sms_template": sms_template or fallback["sms_template"],
    }



async def _generate_request_id() -> str:
    while True:
        candidate = f"REQ-{secrets.token_hex(8).upper()}"
        existing = await db_manager.location_requests.find_one(
            {"request_id": candidate},
            {"_id": 1},
        )
        if not existing:
            return candidate


async def _write_audit_event(
    *,
    request_id: str,
    actor_id: str,
    actor_role: UserRole,
    event_type: AuditEventType,
    details: dict,
) -> None:
    event = AuditLogDocument(
        request_id=request_id,
        actor_id=actor_id,
        actor_role=actor_role,
        event_type=event_type,
        details=details,
    )
    await db_manager.audit_logs.insert_one(event.model_dump(mode="json"))


@router.post(
    "",
    response_model=ApiResponse[LocationRequestResponse],
    status_code=status.HTTP_201_CREATED,
    summary="Create location request (Officer workflow - Phase 2)",
)
async def create_request(
    payload: LocationRequestCreate,
    principal: AuthenticatedPrincipal = Depends(get_current_principal),
) -> ApiResponse[LocationRequestResponse]:
    """Create and persist a new officer location request."""
    require_role(principal, UserRole.OFFICER, UserRole.ADMIN)

    if not await _is_operator_active(payload.operator_code):
        raise ValidationException(
            message="Operator is not approved or currently inactive.",
            field="operator_code",
            details={"operator_code": payload.operator_code},
        )

    request_id = await _generate_request_id()
    officer_id = principal.principal_id

    document = LocationRequestDocument.create_new(
        request_id=request_id,
        case_id=payload.case_id,
        target_phone_number=payload.target_phone_number,
        operator_code=payload.operator_code,
        submitting_officer_id=officer_id,
        remarks=payload.remarks,
    )

    await db_manager.location_requests.insert_one(document.model_dump(mode="json"))
    await _write_audit_event(
        request_id=document.request_id,
        actor_id=officer_id,
        actor_role=UserRole.OFFICER,
        event_type=AuditEventType.REQUEST_CREATED,
        details={
            "status": document.status.value,
            "operator_code": document.operator_code,
        },
    )

    response_payload = _to_response(document)
    return ApiResponse(
        success=True,
        message=(
            "Location request created successfully. Use the explicit share-link "
            "endpoint to deliver a one-time bearer link."
        ),
        data=response_payload,
    )

@router.get(
    "/io/pending",
    response_model=ApiResponse[list[LocationRequestResponse]],
    status_code=status.HTTP_200_OK,
    summary="List pending location requests for IO execution",
)
async def get_pending_io_requests(
    principal: AuthenticatedPrincipal = Depends(get_current_principal),
) -> ApiResponse[list[LocationRequestResponse]]:
    """Return location requests awaiting IO review."""
    require_role(principal, UserRole.IO, UserRole.ADMIN)

    cursor = db_manager.location_requests.find(
        {"status": RequestState.PENDING_IO_REVIEW.value}
    ).sort("created_at", -1)

    documents: list[LocationRequestResponse] = []

    async for data in cursor:
        data.pop("_id", None)
        document = LocationRequestDocument.model_validate(data)
        documents.append(_to_response(document))

    return ApiResponse(
        success=True,
        message="Pending IO requests retrieved successfully.",
        data=documents,
    )

@router.get(
    "/{request_id}",
    response_model=ApiResponse[LocationRequestResponse],
    status_code=status.HTTP_200_OK,
    summary="Retrieve request details (Phase 2)",
)
async def get_request(
    principal: AuthenticatedPrincipal = Depends(get_current_principal),
    request_id: str = Path(
        ...,
        description="Unique opaque request identifier",
        examples=["REQ-A13F55D0B662E2CF"],
    ),
) -> ApiResponse[LocationRequestResponse]:
    """Fetch location request details with masked target number."""
    data = await db_manager.location_requests.find_one({"request_id": request_id})
    if not data:
        raise ResourceNotFoundError(
            message="Location request not found.",
            resource_id=request_id,
        )

    data.pop("_id", None)
    document = LocationRequestDocument.model_validate(data)
    if not can_access_request(principal, document.submitting_officer_id):
        raise ResourceNotFoundError(message="Location request not found.")

    return ApiResponse(
        success=True,
        message="Location request retrieved successfully.",
        data=_to_response(document),
    )


@router.post(
    "/{request_id}/share-link",
    response_model=ApiResponse[LocationRequestResponse],
    status_code=status.HTTP_200_OK,
    summary="Mint an explicit one-time IO review link",
)
async def mint_share_link(
    request: Request,
    principal: AuthenticatedPrincipal = Depends(get_current_principal),
    request_id: str = Path(..., description="Unique opaque request identifier"),
) -> ApiResponse[LocationRequestResponse]:
    """Generate and return a raw share link only through an explicit operation."""
    data = await db_manager.location_requests.find_one({"request_id": request_id})
    if not data:
        raise ResourceNotFoundError(message="Location request not found.")

    data.pop("_id", None)
    document = LocationRequestDocument.model_validate(data)
    if (
        principal.role == UserRole.OFFICER
        and principal.principal_id != document.submitting_officer_id
    ):
        raise ResourceNotFoundError(message="Location request not found.")
    require_role(principal, UserRole.OFFICER, UserRole.ADMIN)

    now = datetime.now(timezone.utc)
    settings = get_settings()
    raw_share_token = secrets.token_urlsafe(32)
    share_token_hash = hashlib.sha256(raw_share_token.encode("utf-8")).hexdigest()
    share_token = ShareTokenInfo(
        token_hash=share_token_hash,
        expires_at=now + timedelta(hours=settings.request_token_expire_hours),
    )

    update_result = await db_manager.location_requests.update_one(
        {"request_id": document.request_id},
        {
            "$set": {
                "share_token": share_token.model_dump(mode="json"),
                "updated_at": now,
            }
        },
    )
    if update_result.modified_count != 1:
        raise ResourceNotFoundError(message="Location request not found.")

    refreshed = await db_manager.location_requests.find_one(
        {"request_id": document.request_id}
    )
    if not refreshed:
        raise ResourceNotFoundError(message="Location request not found.")
    refreshed.pop("_id", None)
    refreshed_document = LocationRequestDocument.model_validate(refreshed)

    return ApiResponse(
        success=True,
        message=(
            "Share link minted. The raw bearer token is returned only in this "
            "explicit response and is not persisted."
        ),
        data=_to_response(
            refreshed_document,
            shareable_link=_build_shareable_link(request, raw_share_token),
        ),
    )


@router.post(
    "/{request_id}/execute",
    response_model=ApiResponse[dict],
    status_code=status.HTTP_200_OK,
    summary="Authorize and trigger IO SMS dispatch (Phase 3)",
)
async def execute_request(
    payload: LocationExecuteRequest,
    principal: AuthenticatedPrincipal = Depends(get_current_principal),
    request_id: str = Path(..., description="Unique request identifier"),
) -> ApiResponse[dict]:
    """Authorize IO execution, persist dispatch metadata, and provide approved carrier instructions."""
    require_role(principal, UserRole.IO, UserRole.ADMIN)

    data = await db_manager.location_requests.find_one({"request_id": request_id})
    if not data:
        raise ResourceNotFoundError(message="Location request not found.")

    data.pop("_id", None)
    document = LocationRequestDocument.model_validate(data)

    if not await _is_operator_active(document.operator_code):
        raise ValidationException(
            message="Operator is not approved or currently inactive.",
            field="operator_code",
            details={"operator_code": document.operator_code},
        )

    if not is_valid_transition(document.status, RequestState.EXECUTING):
        raise InvalidStateTransitionError(
            current_state=document.status.value,
            target_state=RequestState.EXECUTING.value,
        )

    operator_config = await _get_operator_dispatch_config(document.operator_code)
    raw_target_phone = document.decrypt_target_phone_number()
    sms_body = _format_sms_template(operator_config["sms_template"], raw_target_phone)
    sim_slot_index = payload.sim_slot_index if payload.sim_slot_index is not None else 0

    dispatch_instructions = {
        "service_number": operator_config["service_number"],
        "sms_body": sms_body,
        "operator_code": document.operator_code,
        "sim_slot_index": sim_slot_index,
    }

    now = datetime.now(timezone.utc)
    update_result = await db_manager.location_requests.update_one(
        {"request_id": request_id, "status": document.status.value},
        {
            "$set": {
                "status": RequestState.EXECUTING.value,
                "executing_io_id": principal.principal_id,
                "execution_info.io_device_id": payload.io_device_id,
                "execution_info.sim_slot_index": sim_slot_index,
                "execution_info.dispatched_at": now,
                "updated_at": now,
            }
        },
    )
    if update_result.modified_count != 1:
        latest = await db_manager.location_requests.find_one({"request_id": request_id})
        if not latest:
            raise ResourceNotFoundError(message="Location request not found.")
        latest_status = latest.get("status", "UNKNOWN")
        raise InvalidStateTransitionError(
            current_state=str(latest_status),
            target_state=RequestState.EXECUTING.value,
            message="Request state changed before execution could be triggered.",
        )

    await _write_audit_event(
        request_id=request_id,
        actor_id=principal.principal_id,
        actor_role=principal.role,
        event_type=AuditEventType.EXECUTION_TRIGGERED,
        details={
            "previous_status": document.status.value,
            "status": RequestState.EXECUTING.value,
            "io_device_id": payload.io_device_id,
            "sim_slot_index": sim_slot_index,
            "operator_code": document.operator_code,
            "execution_boundary": "android_device",
        },
    )

    return ApiResponse(
        success=True,
        message=(
            "Execution authorized and recorded. Backend did not dispatch SMS; "
            "Android device execution boundary remains enforced."
        ),
        data={
            "request_id": request_id,
            "status": RequestState.EXECUTING.value,
            "executing_io_id": principal.principal_id,
            "io_device_id": payload.io_device_id,
            "sim_slot_index": sim_slot_index,
            "dispatched_at": now,
            "dispatch_instructions": dispatch_instructions,
        },
    )


@router.post(
    "/{request_id}/send-status",
    response_model=ApiResponse[dict],
    status_code=status.HTTP_200_OK,
    summary="Record SMS dispatch outcome from IO device (Phase 3)",
)
async def record_send_status(
    payload: LocationSendStatusUpdate,
    principal: AuthenticatedPrincipal = Depends(get_current_principal),
    request_id: str = Path(..., description="Unique request identifier"),
) -> ApiResponse[dict]:
    """Record device SMS transmission outcome and update lifecycle state."""
    require_role(principal, UserRole.IO, UserRole.ADMIN)

    data = await db_manager.location_requests.find_one({"request_id": request_id})
    if not data:
        raise ResourceNotFoundError(message="Location request not found.")

    data.pop("_id", None)
    document = LocationRequestDocument.model_validate(data)

    target_state = (
        RequestState.WAITING_RESPONSE
        if payload.success
        else RequestState.SMS_FAILED
    )

    if not is_valid_transition(document.status, target_state):
        raise InvalidStateTransitionError(
            current_state=document.status.value,
            target_state=target_state.value,
        )

    now = datetime.now(timezone.utc)
    update_fields = {
        "status": target_state.value,
        "updated_at": now,
        "execution_info.attempt_count": document.execution_info.attempt_count + 1,
    }
    if payload.success:
        update_fields["execution_info.delivery_status"] = (
            payload.delivery_status or "SENT"
        )
    else:
        update_fields["execution_info.last_error"] = (
            payload.error_message or "SMS transmission failed"
        )

    update_result = await db_manager.location_requests.update_one(
        {"request_id": request_id, "status": document.status.value},
        {"$set": update_fields},
    )
    if update_result.modified_count != 1:
        raise InvalidStateTransitionError(
            current_state=document.status.value,
            target_state=target_state.value,
            message="Request state changed concurrently.",
        )

    event_type = (
        AuditEventType.SMS_DISPATCHED
        if payload.success
        else AuditEventType.SMS_FAILED
    )
    audit_details = {
        "previous_status": document.status.value,
        "status": target_state.value,
        "success": payload.success,
    }
    if payload.success:
        audit_details["delivery_status"] = payload.delivery_status or "SENT"
    else:
        audit_details["error"] = payload.error_message or "SMS transmission failed"

    await _write_audit_event(
        request_id=request_id,
        actor_id=principal.principal_id,
        actor_role=principal.role,
        event_type=event_type,
        details=audit_details,
    )

    return ApiResponse(
        success=True,
        message=(
            "SMS dispatch confirmed; awaiting carrier response."
            if payload.success
            else "SMS transmission failed; request state updated."
        ),
        data={
            "request_id": request_id,
            "status": target_state.value,
            "updated_at": now,
        },
    )


@router.post(
    "/{request_id}/result",
    response_model=ApiResponse[dict],
    status_code=status.HTTP_200_OK,
    summary="Submit telecom carrier SMS reply (Phase 3)",
)
async def submit_result(
    payload: LocationResultSubmission,
    principal: AuthenticatedPrincipal = Depends(get_current_principal),
    request_id: str = Path(..., description="Unique request identifier"),
) -> ApiResponse[dict]:
    """Capture raw telecom carrier SMS response, preserve forensic integrity, and update state."""
    require_role(principal, UserRole.IO, UserRole.ADMIN)

    data = await db_manager.location_requests.find_one({"request_id": request_id})
    if not data:
        raise ResourceNotFoundError(message="Location request not found.")

    data.pop("_id", None)
    document = LocationRequestDocument.model_validate(data)

    if not is_valid_transition(document.status, RequestState.COMPLETED):
        raise InvalidStateTransitionError(
            current_state=document.status.value,
            target_state=RequestState.COMPLETED.value,
        )

    now = datetime.now(timezone.utc)
    received_at = payload.received_at or now
    raw_hash = hashlib.sha256(payload.raw_sms_content.encode("utf-8")).hexdigest()

    response_info = ResponseInfo(
        raw_sms_content=payload.raw_sms_content,
        sender_address=payload.sender_address,
        received_at=received_at,
        raw_hash_sha256=raw_hash,
    )

    update_result = await db_manager.location_requests.update_one(
        {"request_id": request_id, "status": document.status.value},
        {
            "$set": {
                "status": RequestState.COMPLETED.value,
                "response_info": response_info.model_dump(mode="json"),
                "updated_at": now,
            }
        },
    )
    if update_result.modified_count != 1:
        raise InvalidStateTransitionError(
            current_state=document.status.value,
            target_state=RequestState.COMPLETED.value,
            message="Request state changed concurrently.",
        )

    await _write_audit_event(
        request_id=request_id,
        actor_id=principal.principal_id,
        actor_role=principal.role,
        event_type=AuditEventType.SMS_RESPONSE_RECEIVED,
        details={
            "sender_address": payload.sender_address,
            "raw_hash_sha256": raw_hash,
        },
    )

    await _write_audit_event(
        request_id=request_id,
        actor_id=principal.principal_id,
        actor_role=principal.role,
        event_type=AuditEventType.REQUEST_COMPLETED,
        details={
            "status": RequestState.COMPLETED.value,
            "raw_hash_sha256": raw_hash,
        },
    )

    return ApiResponse(
        success=True,
        message="Telecom carrier SMS response preserved successfully.",
        data={
            "request_id": request_id,
            "status": RequestState.COMPLETED.value,
            "raw_hash_sha256": raw_hash,
            "received_at": received_at,
        },
    )

