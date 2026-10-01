"""Pytest Test Configuration and Fixtures."""

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient

from backend.app.core.config import Settings, get_settings
from backend.app.main import create_application


@pytest.fixture(scope="session")
def test_settings() -> Settings:
    """Return test settings with safe testing defaults."""
    return Settings(
        app_env="testing",
        app_debug=True,
        mongodb_database="ifso_location_test",
        mongodb_timeout_ms=1000,
    )


@pytest_asyncio.fixture
async def async_client(test_settings: Settings) -> AsyncClient:
    """Provide an asynchronous HTTP client wired to the FastAPI test instance."""
    app = create_application()
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://testserver") as client:
        yield client
