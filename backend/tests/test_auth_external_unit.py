"""Focused tests for external JWT authentication; no database required."""
from types import SimpleNamespace

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi import HTTPException

from backend.app.core.auth import _verify_external_jwt
from backend.app.core.config import Settings
from backend.app.models.enums import UserRole


@pytest.fixture
def signing_material(monkeypatch):
    private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    public_key = private_key.public_key()

    class FakeJwksClient:
        def get_signing_key_from_jwt(self, token):
            return SimpleNamespace(key=public_key)

    monkeypatch.setattr("backend.app.core.auth._jwks_client", lambda _url: FakeJwksClient())
    return private_key


def _settings(**kwargs):
    values = {
        "app_env": "production",
        "auth_mode": "external",
        "external_auth_jwks_url": "https://identity.example.invalid/.well-known/jwks.json",
        "external_auth_issuer": "https://identity.example.invalid/",
        "external_auth_audience": "ifso-api",
        "external_auth_role_claim": "role",
        "external_auth_subject_claim": "sub",
    }
    values.update(kwargs)
    return Settings(**values)


def test_external_jwt_requires_trusted_issuer_audience_and_role(signing_material):
    token = jwt.encode(
        {"sub": "io-123", "role": "IO", "iss": "https://identity.example.invalid/", "aud": "ifso-api", "exp": 4_000_000_000},
        signing_material,
        algorithm="RS256",
    )
    principal = _verify_external_jwt(token, _settings())
    assert principal.principal_id == "io-123"
    assert principal.role is UserRole.IO


def test_external_jwt_rejects_role_not_in_application_enum(signing_material):
    token = jwt.encode(
        {"sub": "someone", "role": "SUPERUSER", "iss": "https://identity.example.invalid/", "aud": "ifso-api", "exp": 4_000_000_000},
        signing_material,
        algorithm="RS256",
    )
    with pytest.raises(HTTPException) as error:
        _verify_external_jwt(token, _settings())
    assert error.value.status_code == 401


def test_external_jwt_fails_closed_when_idp_configuration_missing():
    with pytest.raises(HTTPException) as error:
        _verify_external_jwt("anything", _settings(external_auth_jwks_url=None))
    assert error.value.status_code == 503
