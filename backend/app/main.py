"""FastAPI Application Entrypoint for IFSO Location Request Management System.

Configures lifespan lifecycle events, logging, database connections, CORS,
exception handlers, and API routing.
"""

from contextlib import asynccontextmanager
from typing import AsyncGenerator
from fastapi import FastAPI, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from backend.app.core.config import get_settings
from backend.app.core.database import db_manager
from backend.app.core.exceptions import register_exception_handlers
from backend.app.core.logging import get_logger, setup_logging
from backend.app.routes.api import api_v1_router

logger = get_logger("app.main")


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    """Application lifespan manager for startup and shutdown routines."""
    settings = get_settings()

    # Configure structured redacting logger
    setup_logging(log_level=settings.log_level)
    logger.info(
        f"Starting {settings.app_name} [v{settings.app_version}] "
        f"in '{settings.app_env}' environment (debug={settings.app_debug})."
    )

    # Attempt database connection
    await db_manager.connect(settings)

    yield

    # Teardown database connection pool
    logger.info("Initiating graceful shutdown...")
    await db_manager.close()
    logger.info("Application shutdown complete.")


def create_application() -> FastAPI:
    """Application factory for FastAPI instance."""
    settings = get_settings()

    app = FastAPI(
        title=settings.app_name,
        description=(
            "REST API for the IFSO Location Request Management System. "
            "Automates authorized SMS location queries with tamper-evident audit trails."
        ),
        version=settings.app_version,
        docs_url="/docs",
        redoc_url="/redoc",
        openapi_url="/openapi.json",
        lifespan=lifespan,
        debug=settings.app_debug,
    )

    # CORS configuration for development and mobile clients
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # Register centralized exception handlers
    register_exception_handlers(app)

    # Root health check endpoint
    @app.get(
        "/",
        tags=["System & Health"],
        status_code=status.HTTP_200_OK,
        summary="Root health and metadata endpoint",
    )
    async def root_status() -> JSONResponse:
        db_health = await db_manager.check_health()
        return JSONResponse(
            status_code=status.HTTP_200_OK,
            content={
                "status": "healthy" if db_health.get("status") == "connected" else "degraded",
                "app": settings.app_name,
                "version": settings.app_version,
                "environment": settings.app_env,
                "database_status": db_health.get("status"),
                "docs_url": "/docs",
                "api_v1": settings.api_v1_prefix,
            },
        )

    # Register API routes under v1 prefix
    app.include_router(api_v1_router, prefix=settings.api_v1_prefix)

    return app


# Application singleton for ASGI servers (uvicorn backend.app.main:app)
app = create_application()
