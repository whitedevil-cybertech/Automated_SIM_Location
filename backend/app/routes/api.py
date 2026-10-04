"""V1 API Router Aggregator."""

from fastapi import APIRouter
from backend.app.routes.health import router as health_router
from backend.app.routes.operators import router as operators_router
from backend.app.routes.request_links import router as request_links_router
from backend.app.routes.requests import router as requests_router

api_v1_router = APIRouter()

# Register sub-routers
api_v1_router.include_router(health_router)
api_v1_router.include_router(requests_router)
api_v1_router.include_router(request_links_router)
api_v1_router.include_router(operators_router)
