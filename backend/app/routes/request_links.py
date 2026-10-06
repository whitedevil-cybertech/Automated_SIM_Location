"""Secure request-link token access routes (Phase 2)."""

from datetime import datetime, timezone
import hashlib
from fastapi import APIRouter, Depends, Path, status

from backend.app.core.auth import (
    AuthenticatedPrincipal,
    get_current_principal,
    require_role,
)
from backend.app.core.database import db_manager
from backend.app.core.exceptions import ResourceNotFoundError
from backend.app.models.audit_log import AuditLogDocument
from backend.app.models.enums import AuditEventType, RequestState, UserRole
from backend.app.models.location_request import LocationRequestDocument
from backend.app.schemas.common import ApiResponse
from backend.app.schemas.location_request import LocationRequestResponse

router = APIRouter(prefix="/request-links", tags=["Request Links"])


def _to_response(document: LocationRequestDocument) -> LocationRequestResponse:
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
        shareable_link=None,
        has_parsed_result=document.parsed_result is not None,
    )


@router.get(
    "/{token}",
    name="access_request_link",
    response_model=ApiResponse[LocationRequestResponse],
    status_code=status.HTTP_200_OK,
    summary="Redeem secure tokenized request link",
)
async def access_request_link(
    principal: AuthenticatedPrincipal = Depends(get_current_principal),
    token: str = Path(..., min_length=24, description="Opaque share token"),
) -> ApiResponse[LocationRequestResponse]:
    """Redeem tokenized link for one-time request access."""
    require_role(principal, UserRole.IO, UserRole.ADMIN)

    token_hash = hashlib.sha256(token.encode("utf-8")).hexdigest()
    data = await db_manager.location_requests.find_one(
        {"share_token.token_hash": token_hash}
    )
    if not data:
        raise ResourceNotFoundError(message="Invalid or expired request link.")

    data.pop("_id", None)
    document = LocationRequestDocument.model_validate(data)

    share_token = document.share_token
    now = datetime.now(timezone.utc)
    if (
        share_token is None
        or share_token.is_used
        or share_token.expires_at <= now
    ):
        raise ResourceNotFoundError(message="Invalid or expired request link.")

    update_result = await db_manager.location_requests.update_one(
        {
            "request_id": document.request_id,
            "share_token.token_hash": token_hash,
            "share_token.is_used": False,
        },
        {
            "$set": {
                "share_token.is_used": True,
                "share_token.used_at": now,
                "updated_at": now,
                **(
                    {"status": RequestState.PENDING_IO_REVIEW.value}
                    if document.status == RequestState.CREATED
                    else {}
                ),
            }
        },
    )
    if update_result.modified_count != 1:
        raise ResourceNotFoundError(message="Invalid or expired request link.")

    event = AuditLogDocument(
        request_id=document.request_id,
        actor_id=principal.principal_id,
        actor_role=principal.role,
        event_type=AuditEventType.SHAREABLE_LINK_ACCESSED,
        details={"access_method": "token_link"},
    )
    await db_manager.audit_logs.insert_one(event.model_dump(mode="json"))
    if document.status == RequestState.CREATED:
        io_review_event = AuditLogDocument(
            request_id=document.request_id,
            actor_id=principal.principal_id,
            actor_role=principal.role,
            event_type=AuditEventType.IO_REVIEW_STARTED,
            details={
                "previous_status": RequestState.CREATED.value,
                "status": RequestState.PENDING_IO_REVIEW.value,
            },
        )
        await db_manager.audit_logs.insert_one(io_review_event.model_dump(mode="json"))

    refreshed = await db_manager.location_requests.find_one(
        {"request_id": document.request_id}
    )
    if not refreshed:
        raise ResourceNotFoundError(message="Location request not found.")
    refreshed.pop("_id", None)

    return ApiResponse(
        success=True,
        message="Request link accessed successfully.",
        data=_to_response(LocationRequestDocument.model_validate(refreshed)),
    )
