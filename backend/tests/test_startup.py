"""Startup and Health Endpoint Tests."""

import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_app_root_endpoint(async_client: AsyncClient):
    """Verify root endpoint responds with basic system status and metadata."""
    response = await async_client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert "status" in data
    assert data["app"] == "IFSO Location Request Management System"
    assert data["version"] == "0.1.0"
    assert data["docs_url"] == "/docs"


@pytest.mark.asyncio
async def test_health_endpoint(async_client: AsyncClient):
    """Verify v1 health endpoint responds with database diagnostics envelope."""
    response = await async_client.get("/api/v1/health")
    assert response.status_code == 200
    payload = response.json()
    assert payload["success"] is True
    assert "data" in payload
    assert "status" in payload["data"]
    assert "database" in payload["data"]


@pytest.mark.asyncio
async def test_openapi_schema_generation(async_client: AsyncClient):
    """Verify FastAPI automatically generates valid OpenAPI specification."""
    response = await async_client.get("/openapi.json")
    assert response.status_code == 200
    schema = response.json()
    assert schema["info"]["title"] == "IFSO Location Request Management System"
    assert schema["info"]["version"] == "0.1.0"
    assert "/api/v1/health" in schema["paths"]
    assert "/api/v1/requests" in schema["paths"]
    assert "/api/v1/operators" in schema["paths"]


@pytest.mark.asyncio
async def test_request_endpoints_stub_501(async_client: AsyncClient):
    """Verify Phase 2+ endpoints are defined but return 501 Not Implemented."""
    response = await async_client.post(
        "/api/v1/requests",
        json={
            "case_id": "FIR-2026-001",
            "target_phone_number": "9876543210",
            "operator_code": "JIO",
        },
    )
    assert response.status_code == 501
    error_body = response.json()
    assert error_body["success"] is False
    assert error_body["error"]["code"] == "NOT_IMPLEMENTED"
