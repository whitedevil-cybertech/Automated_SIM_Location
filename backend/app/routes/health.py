"""System Health and Readiness Router."""

from fastapi import APIRouter, status
from backend.app.core.config import get_settings
from backend.app.core.database import db_manager
from backend.app.schemas.common import ApiResponse, HealthStatusResponse

router = APIRouter(tags=["System & Health"])


@router.get(
    "/health",
    response_model=ApiResponse[HealthStatusResponse],
    status_code=status.HTTP_200_OK,
    summary="System health status and database connectivity check",
)
async def get_health() -> ApiResponse[HealthStatusResponse]:
    """Check health status of the application and its dependencies."""
    settings = get_settings()
    db_status = await db_manager.check_health()

    health_info = HealthStatusResponse(
        status="healthy" if db_status.get("status") == "connected" else "degraded",
        app=settings.app_name,
        version=settings.app_version,
        environment=settings.app_env,
        database=db_status,
    )

    return ApiResponse(
        success=True,
        message="System health check completed.",
        data=health_info,
    )
