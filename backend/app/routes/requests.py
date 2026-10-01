"""Location Request API Routes (Phase 1 Routing Foundation).

Establishes route definitions, OpenAPI specifications, and response conventions
for location requests. Full workflow execution is scheduled for Phase 2+.
"""

from fastapi import APIRouter, HTTPException, Path, status
from backend.app.schemas.common import ApiResponse
from backend.app.schemas.location_request import (
    LocationExecuteRequest,
    LocationRequestCreate,
    LocationRequestResponse,
    LocationResultSubmission,
)

router = APIRouter(prefix="/requests", tags=["Location Requests"])


@router.post(
    "",
    response_model=ApiResponse[LocationRequestResponse],
    status_code=status.HTTP_501_NOT_IMPLEMENTED,
    summary="Create location request (Officer workflow - Phase 2)",
)
async def create_request(
    payload: LocationRequestCreate,
) -> ApiResponse[LocationRequestResponse]:
    """Endpoint convention for creating a new location request.

    Will be fully implemented with persistence and tokenized links in Phase 2.
    """
    raise HTTPException(
        status_code=status.HTTP_501_NOT_IMPLEMENTED,
        detail="Location request creation is scheduled for Phase 2 (Officer Request Management).",
    )


@router.get(
    "/{request_id}",
    response_model=ApiResponse[LocationRequestResponse],
    status_code=status.HTTP_501_NOT_IMPLEMENTED,
    summary="Retrieve request details (Phase 2)",
)
async def get_request(
    request_id: str = Path(
        ...,
        description="Unique request identifier or token",
        examples=["REQ-2026-00041"],
    ),
) -> ApiResponse[LocationRequestResponse]:
    """Endpoint convention for fetching location request details.

    Target numbers are always returned in masked format.
    """
    raise HTTPException(
        status_code=status.HTTP_501_NOT_IMPLEMENTED,
        detail="Request retrieval workflow is scheduled for Phase 2.",
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
