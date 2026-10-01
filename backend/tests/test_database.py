"""Database Connection and Offline Handling Tests."""

import pytest
from backend.app.core.config import Settings
from backend.app.core.database import DatabaseManager
from backend.app.core.exceptions import DatabaseConnectionError


@pytest.mark.asyncio
async def test_database_manager_offline_graceful_handling():
    """Verify DatabaseManager handles unavailable MongoDB safely without unhandled crashes."""
    manager = DatabaseManager()
    # Attempt connection with very short timeout to non-existent port
    dummy_settings = Settings(
        mongodb_uri="mongodb://127.0.0.1:29999",
        mongodb_database="ifso_test_nonexistent",
        mongodb_timeout_ms=300,
    )

    connected = await manager.connect(dummy_settings)
    assert connected is False
    assert manager.is_connected is False

    health = await manager.check_health()
    assert health["status"] == "disconnected"

    # Accessing collections on disconnected manager must raise DatabaseConnectionError safely
    with pytest.raises(DatabaseConnectionError):
        _ = manager.location_requests

    await manager.close()
