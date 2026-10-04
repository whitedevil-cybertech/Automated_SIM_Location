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
from backend.app.core.exceptions import ResourceNotFoundError, ValidationException
from backend.app.models.audit_log import AuditLogDocument
from backend.app.models.enums import AuditEventType, UserRole
from backend.app.models.location_request import LocationRequestDocument, ShareTokenInfo
from backend.app.routes.operators import DEMO_OPERATORS
from backend.app.schemas.common import ApiResponse
from backend.app.schemas.location_request import (
    LocationExecuteRequest,
    LocationRequestCreate,
    LocationRequestResponse,
    LocationResultSubmission,
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
    status_code=status.HTTP_501_NOT_IMPLEMENTED,
    summary="Authorize and trigger IO SMS dispatch (Phase 3)",
)
async def execute_request(
    payload: LocationExecuteRequest,
    request_id: str = Path(..., description="Unique request identifier"),
) -> ApiResponse[dict]:
    """Endpoint convention for IO authorization and SMS dispatch initiation."""
    raise HTTPException(
        status_code=status.HTTP_501_NOT_IMPLEMENTED,
        detail="IO SMS execution workflow is scheduled for Phase 3.",
    )


@router.post(
    "/{request_id}/result",
    response_model=ApiResponse[dict],
    status_code=status.HTTP_501_NOT_IMPLEMENTED,
    summary="Submit telecom carrier SMS reply (Phase 3/4)",
)
async def submit_result(
    payload: LocationResultSubmission,
    request_id: str = Path(..., description="Unique request identifier"),
) -> ApiResponse[dict]:
    """Endpoint convention for raw SMS response submission and parsing."""
    raise HTTPException(
        status_code=status.HTTP_501_NOT_IMPLEMENTED,
        detail="SMS response ingestion is scheduled for Phase 3/4.",
    )
