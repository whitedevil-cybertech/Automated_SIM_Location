"""Pytest Test Configuration and Fixtures."""

import copy
from types import SimpleNamespace
from typing import Any, Dict
import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient

from backend.app.core.config import Settings, get_settings
from backend.app.core.database import db_manager
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


def _get_nested(document: Dict[str, Any], path: str) -> Any:
    current: Any = document
    for part in path.split("."):
        if not isinstance(current, dict) or part not in current:
            return None
        current = current[part]
    return current


def _set_nested(document: Dict[str, Any], path: str, value: Any) -> None:
    current = document
    parts = path.split(".")
    for part in parts[:-1]:
        if part not in current or not isinstance(current[part], dict):
            current[part] = {}
        current = current[part]
    current[parts[-1]] = value


def _matches(document: Dict[str, Any], query: Dict[str, Any]) -> bool:
    for key, expected in query.items():
        if _get_nested(document, key) != expected:
            return False
    return True

class FakeCursor:
    def __init__(self, documents: list[Dict[str, Any]]) -> None:
        self.documents = documents

    def sort(self, key: str, direction: int):
        self.documents.sort(
            key=lambda document: document.get(key) or "",
            reverse=direction < 0,
        )
        return self

    def __aiter__(self):
        async def iterate():
            for document in self.documents:
                yield copy.deepcopy(document)

        return iterate()

class FakeCollection:
    def __init__(self) -> None:
        self.documents: list[Dict[str, Any]] = []

    async def insert_one(self, document: Dict[str, Any]):
        self.documents.append(copy.deepcopy(document))
        return SimpleNamespace(inserted_id=len(self.documents))

    async def find_one(
        self,
        query: Dict[str, Any],
        projection: Dict[str, int] | None = None,
    ):
        for document in self.documents:
            if _matches(document, query):
                return copy.deepcopy(document)
        return None

    def find(self, query: Dict[str, Any]) -> FakeCursor:
        matching_documents = [
            copy.deepcopy(document)
            for document in self.documents
            if _matches(document, query)
        ]
        return FakeCursor(matching_documents)

    async def update_one(
        self,
        query: Dict[str, Any],
        update: Dict[str, Any],
    ):
        for document in self.documents:
            if _matches(document, query):
                for key, value in update.get("$set", {}).items():
                    _set_nested(document, key, value)
                return SimpleNamespace(modified_count=1)
        return SimpleNamespace(modified_count=0)


class FakeDatabase:
    def __init__(self) -> None:
        self.location_requests = FakeCollection()
        self.operators = FakeCollection()
        self.audit_logs = FakeCollection()

    def __getitem__(self, name: str):
        return getattr(self, name)


@pytest.fixture
def fake_database(monkeypatch: pytest.MonkeyPatch) -> FakeDatabase:
    fake_db = FakeDatabase()
    monkeypatch.setattr(db_manager, "get_database", lambda: fake_db)
    return fake_db
