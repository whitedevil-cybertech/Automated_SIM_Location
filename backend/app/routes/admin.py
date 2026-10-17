"""Read-only administrative monitoring APIs backed by persisted records.

Configuration mutation and account administration are intentionally not exposed
until the project has an approved provisioning workflow and audited write policy.
"""
from collections import Counter
from datetime import datetime, timezone
from fastapi import HTTPException, Path
from pydantic import BaseModel, Field
from typing import Any

from fastapi import APIRouter, Depends, Query, status

from backend.app.core.auth import AuthenticatedPrincipal, get_current_principal, require_role
from backend.app.core.database import db_manager
from backend.app.models.enums import RequestState, UserRole
from backend.app.models.location_request import LocationRequestDocument
from backend.app.schemas.common import ApiResponse
from backend.app.routes.requests import _to_response

router = APIRouter(prefix="/admin", tags=["Administration"])


@router.get("/dashboard", response_model=ApiResponse[dict], status_code=status.HTTP_200_OK)
async def get_admin_dashboard(
    principal: AuthenticatedPrincipal = Depends(get_current_principal),
) -> ApiResponse[dict]:
    """Return real aggregate counts and recent audit events; never synthesize records."""
    require_role(principal, UserRole.ADMIN)

    requests = []
    async for raw in db_manager.location_requests.find({}).sort("created_at", -1):
        raw.pop("_id", None)
        requests.append(LocationRequestDocument.model_validate(raw))

    states = Counter(item.status.value for item in requests)
    operators = []
    async for operator in db_manager.operators.find({}):
        operators.append(operator)

    audit_events = []
    async for event in db_manager.audit_logs.find({}).sort("timestamp", -1):
        # Do not expose arbitrary details/raw evidence in the overview response.
        audit_events.append({
            "audit_id": event.get("audit_id"),
            "request_id": event.get("request_id"),
            "timestamp": event.get("timestamp"),
            "actor_id": event.get("actor_id"),
            "actor_role": event.get("actor_role"),
            "event_type": event.get("event_type"),
        })
        if len(audit_events) >= 10:
            break

    account_counts = Counter()
    async for account in db_manager.user_accounts.find({}):
        account_counts[account.get("status", "UNKNOWN")] += 1

    data = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "request_total": len(requests),
        "requests_by_state": dict(states),
        "operator_configurations": {
            "total": len(operators),
            "active": sum(1 for op in operators if bool(op.get("is_active", False))),
            "inactive": sum(1 for op in operators if not bool(op.get("is_active", False))),
        },
        "account_counts": dict(account_counts),
        "recent_audit_events": audit_events,
        "recent_requests": [
            _to_response(item).model_copy(update={
                "raw_sms_content": None,
                "response_sender_address": None,
                "response_received_at": None,
                "response_sha256": None,
            }).model_dump(mode="json")
            for item in requests[:20]
        ],
        "capabilities": {
            "request_monitoring": True,
            "operator_configuration_overview": True,
            "operator_configuration_mutation": False,
            "account_administration": True,
            "audit_event_view": True,
        },
    }
    return ApiResponse(success=True, message="Administrative overview retrieved.", data=data)


@router.get("/requests", response_model=ApiResponse[list[dict]], status_code=status.HTTP_200_OK)
async def get_admin_requests(
    limit: int = Query(default=50, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    principal: AuthenticatedPrincipal = Depends(get_current_principal),
) -> ApiResponse[list[dict]]:
    """Paginated administrative request inspection using masked response schemas."""
    require_role(principal, UserRole.ADMIN)
    items = []
    async for raw in db_manager.location_requests.find({}).sort("created_at", -1):
        raw.pop("_id", None)
        items.append(_to_response(LocationRequestDocument.model_validate(raw)).model_copy(update={
            "raw_sms_content": None,
            "response_sender_address": None,
            "response_received_at": None,
            "response_sha256": None,
        }).model_dump(mode="json"))
    return ApiResponse(
        success=True,
        message="Administrative requests retrieved.",
        data=items[offset:offset + limit],
    )


class AccountDecision(BaseModel):
    decision_note: str | None = Field(default=None, max_length=500)

@router.get("/accounts", response_model=ApiResponse[list[dict]])
async def list_accounts(
    status_filter: str | None = Query(default=None, alias="status", pattern="^(PENDING_APPROVAL|APPROVED|REJECTED|DISABLED)$"),
    principal: AuthenticatedPrincipal = Depends(get_current_principal),
) -> ApiResponse[list[dict]]:
    require_role(principal, UserRole.ADMIN)
    results = []
    async for account in db_manager.user_accounts.find({}).sort("created_at", -1):
        if status_filter and account.get("status") != status_filter:
            continue
        results.append({key: account.get(key) for key in ("user_id", "full_name", "email", "unit", "phone", "requested_role", "status", "created_at", "approved_by", "approved_at", "decision_note")})
    return ApiResponse(success=True, message="Enrollment records retrieved.", data=results)

@router.post("/accounts/{user_id}/approve", response_model=ApiResponse[dict])
async def approve_account(user_id: str = Path(..., min_length=3), principal: AuthenticatedPrincipal = Depends(get_current_principal)) -> ApiResponse[dict]:
    require_role(principal, UserRole.ADMIN)
    account = await db_manager.user_accounts.find_one({"user_id": user_id})
    if not account or account.get("status") != "PENDING_APPROVAL":
        raise HTTPException(status_code=404, detail="Pending enrollment not found.")
    now = datetime.now(timezone.utc)
    await db_manager.user_accounts.update_one({"user_id": user_id}, {"$set": {"status": "APPROVED", "approved_by": principal.principal_id, "approved_at": now.isoformat()}})
    return ApiResponse(success=True, message="Enrollment approved. Credential provisioning remains governed by the configured identity provider.", data={"user_id": user_id, "status": "APPROVED", "approved_by": principal.principal_id, "approved_at": now.isoformat()})

@router.post("/accounts/{user_id}/reject", response_model=ApiResponse[dict])
async def reject_account(user_id: str = Path(..., min_length=3), payload: AccountDecision = AccountDecision(), principal: AuthenticatedPrincipal = Depends(get_current_principal)) -> ApiResponse[dict]:
    require_role(principal, UserRole.ADMIN)
    account = await db_manager.user_accounts.find_one({"user_id": user_id})
    if not account or account.get("status") != "PENDING_APPROVAL":
        raise HTTPException(status_code=404, detail="Pending enrollment not found.")
    await db_manager.user_accounts.update_one({"user_id": user_id}, {"$set": {"status": "REJECTED", "approved_by": principal.principal_id, "approved_at": datetime.now(timezone.utc).isoformat(), "decision_note": payload.decision_note}})
    return ApiResponse(success=True, message="Enrollment rejected.", data={"user_id": user_id, "status": "REJECTED"})
