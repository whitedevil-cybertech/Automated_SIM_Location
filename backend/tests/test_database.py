"""PostgreSQL connection and offline handling tests."""
import pytest
from backend.app.core.config import Settings
from backend.app.core.database import DatabaseManager
from backend.app.core.exceptions import DatabaseConnectionError


@pytest.mark.asyncio
async def test_database_manager_offline_graceful_handling():

    manager = DatabaseManager()
    settings = Settings(
        app_env="testing",
        database_url="postgresql+psycopg://invalid:invalid@127.0.0.1:29999/ifso_test",
        database_pool_timeout_seconds=1,
    )
    connected = await manager.connect(settings)
    assert connected is False
    assert manager.is_connected is False
    assert (await manager.check_health())["status"] == "disconnected"
    with pytest.raises(DatabaseConnectionError):
        _ = manager.location_requests

    await manager.close()
