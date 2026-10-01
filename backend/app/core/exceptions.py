"""Centralized Exception Definitions and Handlers.

Provides standard domain exceptions and maps them to consistent JSON error responses.
"""

from typing import Any, Dict, Optional
from fastapi import FastAPI, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from backend.app.core.logging import get_logger

logger = get_logger(__name__)


class IFSOException(Exception):
    """Base application exception for IFSO system."""

    def __init__(
        self,
        message: str,
        code: str = "INTERNAL_ERROR",
        status_code: int = status.HTTP_500_INTERNAL_SERVER_ERROR,
        details: Optional[Dict[str, Any]] = None,
    ):
        super().__init__(message)
        self.message = message
        self.code = code
        self.status_code = status_code
        self.details = details or {}


class DatabaseConnectionError(IFSOException):
    """Raised when the database connection fails or is unavailable."""

    def __init__(
        self,
        message: str = "Database service is currently unreachable.",
        details: Optional[Dict[str, Any]] = None,
    ):
        super().__init__(
            message=message,
            code="DATABASE_UNAVAILABLE",
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            details=details,
        )


class ResourceNotFoundError(IFSOException):
    """Raised when a requested resource does not exist."""

    def __init__(
        self,
        message: str = "The requested resource was not found.",
        resource_id: Optional[str] = None,
    ):
        details = {"resource_id": resource_id} if resource_id else {}
        super().__init__(
            message=message,
            code="RESOURCE_NOT_FOUND",
            status_code=status.HTTP_404_NOT_FOUND,
            details=details,
        )


class InvalidStateTransitionError(IFSOException):
    """Raised when attempting an unauthorized or invalid state transition."""

    def __init__(
        self,
        current_state: str,
        target_state: str,
        message: Optional[str] = None,
    ):
        msg = (
            message
            or f"Invalid request transition from '{current_state}' to '{target_state}'."
        )
        super().__init__(
            message=msg,
            code="INVALID_STATE_TRANSITION",
            status_code=status.HTTP_409_CONFLICT,
            details={
                "current_state": current_state,
                "target_state": target_state,
            },
        )


class ValidationException(IFSOException):
    """Raised when domain-level data validation fails."""

    def __init__(
        self,
        message: str,
        field: Optional[str] = None,
        details: Optional[Dict[str, Any]] = None,
    ):
        dtl = details or {}
        if field:
            dtl["field"] = field
        super().__init__(
            message=message,
            code="VALIDATION_ERROR",
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            details=dtl,
        )


def create_error_response(
    code: str,
    message: str,
    status_code: int,
    details: Optional[Dict[str, Any]] = None,
) -> JSONResponse:
    """Helper to generate standard JSON error response envelope."""
    payload: Dict[str, Any] = {
        "success": False,
        "error": {
            "code": code,
            "message": message,
            "details": details or {},
        },
    }
    return JSONResponse(status_code=status_code, content=payload)


def register_exception_handlers(app: FastAPI) -> None:
    """Attach centralized exception handlers to the FastAPI application instance."""

    @app.exception_handler(IFSOException)
    async def handle_ifso_exception(request: Request, exc: IFSOException) -> JSONResponse:
        logger.error(f"Application error [{exc.code}]: {exc.message} | Details: {exc.details}")
        return create_error_response(
            code=exc.code,
            message=exc.message,
            status_code=exc.status_code,
            details=exc.details,
        )

    @app.exception_handler(StarletteHTTPException)
    async def handle_http_exception(
        request: Request, exc: StarletteHTTPException
    ) -> JSONResponse:
        code_map = {
            400: "BAD_REQUEST",
            401: "UNAUTHORIZED",
            403: "FORBIDDEN",
            404: "NOT_FOUND",
            405: "METHOD_NOT_ALLOWED",
            409: "CONFLICT",
            501: "NOT_IMPLEMENTED",
            503: "SERVICE_UNAVAILABLE",
        }
        code = code_map.get(exc.status_code, "HTTP_ERROR")
        return create_error_response(
            code=code,
            message=str(exc.detail),
            status_code=exc.status_code,
        )

    @app.exception_handler(RequestValidationError)
    async def handle_validation_error(
        request: Request, exc: RequestValidationError
    ) -> JSONResponse:
        errors = []
        for err in exc.errors():
            loc = " -> ".join([str(l) for l in err.get("loc", [])])
            msg = err.get("msg", "Invalid value")
            errors.append({"location": loc, "message": msg, "type": err.get("type")})
        return create_error_response(
            code="REQUEST_VALIDATION_FAILED",
            message="The submitted request body or parameters failed validation.",
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            details={"validation_errors": errors},
        )

    @app.exception_handler(Exception)
    async def handle_unexpected_exception(request: Request, exc: Exception) -> JSONResponse:
        logger.exception("Unhandled server exception caught by root handler.")
        return create_error_response(
            code="INTERNAL_SERVER_ERROR",
            message="An unexpected server error occurred. Please contact the administrator.",
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        )
