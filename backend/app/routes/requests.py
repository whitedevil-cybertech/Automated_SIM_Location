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
from backend.app.core.field_crypto import decrypt_sensitive_text, encrypt_sensitive_text
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
    # Public app-facing base is configurable independently from the API host.
    settings = get_settings()
    public_base = getattr(settings, "public_share_base_url", None)
    if public_base and public_base.strip():
        return f"{public_base.rstrip('/')}/{raw_token}"
    return f"ifso://request/{raw_token}"


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
        raw_sms_content=(
            (
                document.response_info.raw_sms_content
                if document.response_info.raw_sms_content is not None
                else decrypt_sensitive_text(document.response_info.raw_sms_content_encrypted)
                if document.response_info.raw_sms_content_encrypted is not None
                else None
            )
            if document.response_info is not None else None
        ),
        response_sender_address=(
            document.response_info.sender_address
            if document.response_info is not None else None
        ),
        response_received_at=(
            document.response_info.received_at
            if document.response_info is not None else None
        ),
        response_sha256=(
            document.response_info.raw_hash_sha256
            if document.response_info is not None else None
        ),
    )


async def _is_operator_active(operator_code: str) -> bool:
    db_operator = await db_manager.operators.find_one({"operator_code": operator_code})
    if db_operator is not None:
        return bool(db_operator.get("is_active", False))

    settings = get_settings()
    # Synthetic operator choices exist only in local development/testing. They
    # are not trusted configuration and can never authorize production requests.
    if settings.app_env in {"development", "testing"}:
        return any(
            op.operator_code == operator_code and op.is_active for op in DEMO_OPERATORS
        )
    return False


# Telecom dispatch values are intentionally not guessed. An operator must have
# an explicitly approved service number and SMS template in PostgreSQL before
# the execution endpoint can return dispatch instructions.


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
    """Load an approved operator profile; fail closed when integration data is absent."""
    db_operator = await db_manager.operators.find_one({"operator_code": operator_code})
    if not db_operator:
        raise ValidationException(
            message="No approved SMS configuration exists for this operator.",
            field="operator_code",
            details={"operator_code": operator_code, "configuration_required": True},
        )

    service_number = db_operator.get("service_number")
    sms_template = db_operator.get("sms_template")
    if not isinstance(service_number, str) or not service_number.strip():
        raise ValidationException(
            message="The operator profile has no approved SMS destination.",
            field="operator_code",
            details={"operator_code": operator_code, "configuration_required": True},
        )
    if not isinstance(sms_template, str) or not sms_template.strip():
        raise ValidationException(
            message="The operator profile has no approved SMS template.",
            field="operator_code",
            details={"operator_code": operator_code, "configuration_required": True},
        )
    response_sender = db_operator.get("response_sender")
    if not isinstance(response_sender, str) or not response_sender.strip():
        raise ValidationException(
            message="The operator profile has no approved response sender for SMS correlation.",
            field="operator_code",
            details={"operator_code": operator_code, "configuration_required": True},
        )
    return {
        "service_number": service_number.strip(),
        "sms_template": sms_template.strip(),
        "response_sender": response_sender.strip(),
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

    # IO assignment must resolve to a currently approved account; arbitrary IDs are rejected.
    io_account = await db_manager.user_accounts.find_one({"user_id": payload.assigned_io_id.strip()})
    if not io_account or io_account.get("status") != "APPROVED" or io_account.get("requested_role") != "IO":
        raise ValidationException(
            message="Assigned IO does not exist or is not an approved IO account.",
            field="assigned_io_id",
            details={"assigned_io_id": payload.assigned_io_id},
        )

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
        executing_io_id=payload.assigned_io_id.strip(),
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

    # Include requests explicitly shared with the IO even if the IO has not
    # opened/redeemed the one-time link yet. Unshared CREATED requests remain
    # invisible to the IO queue. Once redeemed, the state is PENDING_IO_REVIEW.
    cursor = db_manager.location_requests.find({}).sort("created_at", -1)
    documents: list[LocationRequestResponse] = []

    async for data in cursor:
        data.pop("_id", None)
        document = LocationRequestDocument.model_validate(data)
        is_assigned = document.executing_io_id == principal.principal_id
        is_pending = document.status == RequestState.PENDING_IO_REVIEW and is_assigned
        is_shared_created = (
            document.status == RequestState.CREATED
            and is_assigned
            and document.share_token is not None
            and not document.share_token.is_used
            and document.share_token.expires_at > datetime.now(timezone.utc)
        )
        if principal.role == UserRole.ADMIN or is_pending or is_shared_created:
            documents.append(_to_response(document))

    return ApiResponse(
        success=True,
        message="Pending IO requests retrieved successfully.",
        data=documents,
    )

@router.get(
    "/my",
    response_model=ApiResponse[list[LocationRequestResponse]],
    status_code=status.HTTP_200_OK,
    summary="List requests created by the authenticated officer",
)
async def get_my_requests(
    principal: AuthenticatedPrincipal = Depends(get_current_principal),
    limit: int = 50,
    offset: int = 0,
) -> ApiResponse[list[LocationRequestResponse]]:
    """Return only the current officer's requests; identity is never client-supplied."""
    require_role(principal, UserRole.OFFICER)
    if limit < 1 or limit > 100 or offset < 0:
        raise ValidationException(message="Invalid pagination values.", field="pagination")
    cursor = db_manager.location_requests.find(
        {"submitting_officer_id": principal.principal_id}
    ).sort("created_at", -1)
    records = []
    async for data in cursor:
        data.pop("_id", None)
        records.append(_to_response(
            LocationRequestDocument.model_validate(data)
        ).model_copy(update={
            "raw_sms_content": None,
            "response_sender_address": None,
            "response_received_at": None,
            "response_sha256": None,
        }))
    return ApiResponse(success=True, message="Officer requests retrieved.", data=records[offset:offset + limit])


@router.get(
    "/io/visible",
    response_model=ApiResponse[list[LocationRequestResponse]],
    status_code=status.HTTP_200_OK,
    summary="List requests visible to the authenticated IO",
)
async def get_io_visible_requests(
    principal: AuthenticatedPrincipal = Depends(get_current_principal),
    limit: int = 50,
    offset: int = 0,
) -> ApiResponse[list[LocationRequestResponse]]:
    """Return the current IO's permitted review/processing queue using existing access policy."""
    require_role(principal, UserRole.IO)
    if limit < 1 or limit > 100 or offset < 0:
        raise ValidationException(message="Invalid pagination values.", field="pagination")
    cursor = db_manager.location_requests.find({}).sort("created_at", -1)
    records = []
    now = datetime.now(timezone.utc)
    async for data in cursor:
        data.pop("_id", None)
        document = LocationRequestDocument.model_validate(data)
        shared = document.share_token is not None and (
            not document.share_token.is_used
            and document.share_token.expires_at > now
        )
        # Match the existing queue policy for pending review. Once execution starts,
        # only the IO recorded as executor can see the request in their tracking list.
        visible = (
            principal.role == UserRole.ADMIN
            or (
                document.executing_io_id == principal.principal_id
                and (
                    document.status == RequestState.PENDING_IO_REVIEW
                    or shared
                    or document.status in {
                        RequestState.EXECUTING,
                        RequestState.WAITING_RESPONSE,
                        RequestState.COMPLETED,
                        RequestState.SMS_FAILED,
                        RequestState.TIMEOUT,
                        RequestState.RESPONSE_INVALID,
                    }
                )
            )
        )
        if visible:
            records.append(_to_response(document).model_copy(update={
                "raw_sms_content": None,
                "response_sender_address": None,
                "response_received_at": None,
                "response_sha256": None,
            }))
    return ApiResponse(success=True, message="IO requests retrieved.", data=records[offset:offset + limit])


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
                "status": (
                    RequestState.PENDING_IO_REVIEW.value
                    if document.status == RequestState.CREATED
                    else document.status.value
                ),
                "updated_at": now,
            }
        },
    )
    if update_result.modified_count != 1:
        raise ResourceNotFoundError(message="Location request not found.")

    await _write_audit_event(
        request_id=document.request_id,
        actor_id=principal.principal_id,
        actor_role=principal.role,
        event_type=AuditEventType.SHAREABLE_LINK_CREATED,
        details={
            "status": (
                RequestState.PENDING_IO_REVIEW.value
                if document.status == RequestState.CREATED
                else document.status.value
            ),
            "expires_at": share_token.expires_at.isoformat(),
        },
    )

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
        "response_sender": operator_config.get("response_sender"),
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
                "execution_info.execution_started_at": now,
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

    # Make retries safe when the database update committed but the HTTP
    # response was lost. This does not repeat the mutation or duplicate audit
    # events, and it never moves a request backwards from a later lifecycle state.
    expected_delivery_status = payload.delivery_status or "SENT"
    if payload.success:
        already_recorded_success = (
            document.status in {
                RequestState.WAITING_RESPONSE,
                RequestState.COMPLETED,
                RequestState.TIMEOUT,
                RequestState.RESPONSE_INVALID,
            }
            and document.execution_info.delivery_status == expected_delivery_status
        )
        if already_recorded_success:
            return ApiResponse(
                success=True,
                message="SMS dispatch status was already recorded.",
                data={
                    "request_id": request_id,
                    "status": document.status.value,
                    "updated_at": document.updated_at,
                    "idempotent_replay": True,
                },
            )
    else:
        expected_error = payload.error_message or "SMS transmission failed"
        if (
            document.status == RequestState.SMS_FAILED
            and document.execution_info.last_error == expected_error
        ):
            return ApiResponse(
                success=True,
                message="SMS failure status was already recorded.",
                data={
                    "request_id": request_id,
                    "status": document.status.value,
                    "updated_at": document.updated_at,
                    "idempotent_replay": True,
                },
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
        # Start the response deadline only after the device reports dispatch.
        update_fields["execution_info.dispatched_at"] = now
        update_fields["execution_info.awaiting_response_since"] = now
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

    # Validate the claimed sender against the provider-approved profile before
    # accepting raw SMS as evidence. Do not infer a sender from the destination.
    operator_config = await _get_operator_dispatch_config(document.operator_code)
    expected_sender = operator_config["response_sender"]
    received_sender = (payload.sender_address or "").strip()
    normalize_sender = lambda value: "".join(
        char for char in value.upper() if char.isalnum()
    )
    if not received_sender or normalize_sender(received_sender) != normalize_sender(expected_sender):
        raise ValidationException(
            message="SMS sender does not match the approved operator response sender.",
            field="sender_address",
            details={"operator_code": document.operator_code},
        )

    if not is_valid_transition(document.status, RequestState.COMPLETED):
        raise InvalidStateTransitionError(
            current_state=document.status.value,
            target_state=RequestState.COMPLETED.value,
        )

    now = datetime.now(timezone.utc)
    received_at = payload.received_at or now
    raw_hash = hashlib.sha256(payload.raw_sms_content.encode("utf-8")).hexdigest()

    response_info = ResponseInfo(
        raw_sms_content=None,
        raw_sms_content_encrypted=encrypt_sensitive_text(payload.raw_sms_content),
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