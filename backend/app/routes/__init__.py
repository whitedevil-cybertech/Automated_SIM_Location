"""Routes Package."""

from backend.app.routes.api import api_v1_router
from backend.app.routes.health import router as health_router
from backend.app.routes.operators import router as operators_router
from backend.app.routes.requests import router as requests_router

__all__ = [
    "api_v1_router",
    "health_router",
    "requests_router",
    "operators_router",
]
