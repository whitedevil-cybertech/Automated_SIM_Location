"""Identity endpoints and public account-enrollment requests."""
from datetime import datetime, timezone
import re
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field, field_validator
from backend.app.core.auth import AuthenticatedPrincipal, get_current_principal, require_role
from backend.app.core.database import db_manager
from backend.app.models.enums import UserRole
from backend.app.schemas.common import ApiResponse

router = APIRouter(prefix="/auth", tags=["Authentication"])

class SignupRequest(BaseModel):
    user_id: str = Field(min_length=3, max_length=100)
    full_name: str = Field(min_length=2, max_length=160)
    email: str = Field(min_length=5, max_length=320)
    unit: str = Field(min_length=2, max_length=160)
    phone: str = Field(min_length=10, max_length=20)
    requested_role: str = Field(default="OFFICER")
    @field_validator("email")
    @classmethod
    def normalize_email(cls, value: str) -> str:
        value = value.strip().lower()
        if not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", value):
            raise ValueError("A valid email address is required.")
        return value
    @field_validator("requested_role")
    @classmethod
    def validate_role(cls, value: str) -> str:
        role = value.strip().upper()
        if role not in {"OFFICER", "IO"}:
            raise ValueError("Only Officer or IO enrollment can be requested.")
        return role

@router.post("/signup", response_model=ApiResponse[dict], status_code=status.HTTP_201_CREATED)
async def request_signup(payload: SignupRequest) -> ApiResponse[dict]:
    """Create a pending enrollment request; this does not issue credentials or a session."""
    existing_id = await db_manager.user_accounts.find_one({"user_id": payload.user_id.strip()})
    existing_email = await db_manager.user_accounts.find_one({"email": payload.email})
    if existing_id or existing_email:
        raise HTTPException(status_code=409, detail="An account or enrollment already exists for this ID/email.")
    now = datetime.now(timezone.utc)
    record = {
        "user_id": payload.user_id.strip(), "email": payload.email,
        "full_name": payload.full_name.strip(), "unit": payload.unit.strip(),
        "phone": payload.phone.strip(), "requested_role": payload.requested_role,
        "status": "PENDING_APPROVAL", "created_at": now.isoformat(),
        "approved_by": None, "approved_at": None, "decision_note": None,
    }
    await db_manager.user_accounts.insert_one(record)
    return ApiResponse(success=True, message="Enrollment submitted. An administrator must approve it before account provisioning.", data={"user_id": record["user_id"], "status": record["status"], "requested_role": record["requested_role"]})

@router.get("/me", response_model=ApiResponse[dict], summary="Return authenticated principal")
async def get_me(principal: AuthenticatedPrincipal = Depends(get_current_principal)) -> ApiResponse[dict]:
    # External identity remains the credential authority; if a local enrollment exists,
    # reject it until an administrator has approved it.
    account = await db_manager.user_accounts.find_one({"user_id": principal.principal_id})
    if account and account.get("status") != "APPROVED":
        raise HTTPException(status_code=403, detail="Account is pending administrator approval or is disabled.")
    if account and account.get("requested_role") != principal.role.value:
        raise HTTPException(status_code=403, detail="The authenticated role does not match the administrator-approved role.")
    return ApiResponse(success=True, message="Authenticated principal resolved.", data={"principal_id": principal.principal_id, "role": principal.role.value})


@router.get("/eligible-ios", response_model=ApiResponse[list[dict]])
async def eligible_ios(principal: AuthenticatedPrincipal = Depends(get_current_principal)) -> ApiResponse[list[dict]]:
    """List only administrator-approved IO accounts for assignment selection."""
    if principal.role not in {UserRole.OFFICER, UserRole.ADMIN}:
        raise HTTPException(status_code=403, detail="Only Officers can select an IO assignee.")
    results = []
    async for account in db_manager.user_accounts.find({}):
        if account.get("status") == "APPROVED" and account.get("requested_role") == "IO":
            results.append({"user_id": account.get("user_id"), "full_name": account.get("full_name")})
    return ApiResponse(success=True, message="Approved IO accounts retrieved.", data=results)
