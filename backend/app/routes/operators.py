"""Operator Profiles API Route."""

from typing import List
from fastapi import APIRouter, status
from backend.app.schemas.common import ApiResponse
from backend.app.schemas.operator import OperatorResponse

router = APIRouter(prefix="/operators", tags=["Operator Profiles"])

# Synthetic/development operator list (no production shortcodes or credentials)
DEMO_OPERATORS: List[OperatorResponse] = [
    OperatorResponse(
        operator_code="JIO",
        display_name="Reliance Jio (Demo Profile)",
        is_active=True,
        notes="Standard carrier profile for authorized IO queries.",
    ),
    OperatorResponse(
        operator_code="AIRTEL",
        display_name="Bharti Airtel (Demo Profile)",
        is_active=True,
        notes="Standard carrier profile for authorized IO queries.",
    ),
    OperatorResponse(
        operator_code="VI",
        display_name="Vodafone Idea (Demo Profile)",
        is_active=True,
        notes="Standard carrier profile for authorized IO queries.",
    ),
    OperatorResponse(
        operator_code="BSNL",
        display_name="BSNL (Demo Profile)",
        is_active=True,
        notes="Standard carrier profile for authorized IO queries.",
    ),
]


@router.get(
    "",
    response_model=ApiResponse[List[OperatorResponse]],
    status_code=status.HTTP_200_OK,
    summary="List available telecom operator profiles",
)
async def list_operators() -> ApiResponse[List[OperatorResponse]]:
    """Return available telecom operator profiles for request creation."""
    return ApiResponse(
        success=True,
        message="Available operator profiles retrieved successfully.",
        data=DEMO_OPERATORS,
    )
