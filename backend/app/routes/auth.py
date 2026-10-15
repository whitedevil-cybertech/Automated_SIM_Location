"""Authenticated identity endpoint used to resolve role-based Flutter navigation."""
from fastapi import APIRouter, Depends
from backend.app.core.auth import AuthenticatedPrincipal, get_current_principal
from backend.app.schemas.common import ApiResponse

router = APIRouter(prefix="/auth", tags=["Authentication"])


@router.get("/me", response_model=ApiResponse[dict], summary="Return authenticated principal")
async def get_me(principal: AuthenticatedPrincipal = Depends(get_current_principal)) -> ApiResponse[dict]:
    """Return only the identity and role already established by backend auth."""
    return ApiResponse(
        success=True,
        message="Authenticated principal resolved.",
        data={"principal_id": principal.principal_id, "role": principal.role.value},
    )
