"""Authenticated operator-profile listing.

Only safe display metadata is returned to clients. Telecom dispatch values are
never returned by this endpoint and must be provisioned from approved sources.
"""
from typing import List
from fastapi import APIRouter, Depends, status

from backend.app.core.auth import AuthenticatedPrincipal, get_current_principal
from backend.app.core.config import get_settings
from backend.app.core.database import db_manager
from backend.app.models.enums import UserRole
from backend.app.schemas.common import ApiResponse
from backend.app.schemas.operator import OperatorResponse

router = APIRouter(prefix="/operators", tags=["Operator Profiles"])

# Display-only synthetic entries for local UI development. They do not contain
# dispatch values and are never used as production authorization/configuration.
DEMO_OPERATORS: List[OperatorResponse] = [
    OperatorResponse(operator_code="JIO", display_name="Jio (Unconfigured Demo)", is_active=True,
                     notes="Development placeholder only; no telecom dispatch configuration."),
    OperatorResponse(operator_code="AIRTEL", display_name="Airtel (Unconfigured Demo)", is_active=True,
                     notes="Development placeholder only; no telecom dispatch configuration."),
    OperatorResponse(operator_code="VI", display_name="Vi (Unconfigured Demo)", is_active=True,
                     notes="Development placeholder only; no telecom dispatch configuration."),
    OperatorResponse(operator_code="BSNL", display_name="BSNL (Unconfigured Demo)", is_active=True,
                     notes="Development placeholder only; no telecom dispatch configuration."),
]


@router.get(
    "",
    response_model=ApiResponse[List[OperatorResponse]],
    status_code=status.HTTP_200_OK,
    summary="List selectable operator profiles without dispatch secrets",
)
async def list_operators(
    _principal: AuthenticatedPrincipal = Depends(get_current_principal),
) -> ApiResponse[List[OperatorResponse]]:
    """Return active DB profiles, with display-only placeholders in dev/test."""
    profiles: List[OperatorResponse] = []
    try:
        async for record in db_manager.operators.find({}):
            if not record.get("is_active", False):
                continue
            profiles.append(OperatorResponse(
                operator_code=str(record.get("operator_code", "")),
                display_name=str(record.get("display_name") or record.get("operator_code", "Operator")),
                is_active=True,
                notes=record.get("notes"),
            ))
    except Exception:
        # A disconnected DB is not a reason to return synthetic production data.
        profiles = []

    settings = get_settings()
    if not profiles and settings.app_env in {"development", "testing"}:
        profiles = DEMO_OPERATORS

    return ApiResponse(
        success=True,
        message="Configured operator profiles retrieved. Demo entries, when present, have no dispatch configuration.",
        data=profiles,
    )
