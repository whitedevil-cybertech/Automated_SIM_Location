"""Authentication and authorization helpers.

Development-only static tokens are isolated from staging/production. External
mode validates signed bearer JWTs against an explicitly configured trusted JWKS
endpoint, issuer, audience, subject claim, and role claim. It fails closed when
configuration or identity claims are missing.
"""
from __future__ import annotations

import asyncio
from dataclasses import dataclass
from functools import lru_cache
from typing import Any

import jwt
from jwt import PyJWKClient
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from backend.app.core.config import Settings, get_settings
from backend.app.models.enums import UserRole

bearer_scheme = HTTPBearer(auto_error=False)


@dataclass(frozen=True)
class AuthenticatedPrincipal:
    """Server-derived identity for an authenticated caller."""
    principal_id: str
    role: UserRole


def _parse_development_principal(token: str, settings: Settings) -> AuthenticatedPrincipal | None:
    configured = settings.development_auth_tokens.get(token)
    if not configured:
        return None
    try:
        principal_id, role_value = configured.split(":", 1)
        principal_id = principal_id.strip()
        role = UserRole(role_value.strip().upper())
    except (ValueError, KeyError):
        return None
    if not principal_id:
        return None
    return AuthenticatedPrincipal(principal_id=principal_id, role=role)


@lru_cache(maxsize=4)
def _jwks_client(url: str) -> PyJWKClient:
    """Cache trusted JWKS clients by configured URL."""
    return PyJWKClient(url, cache_keys=True, timeout=5)


def _verify_external_jwt(token: str, settings: Settings) -> AuthenticatedPrincipal:
    required = (settings.external_auth_jwks_url, settings.external_auth_issuer, settings.external_auth_audience)
    if not all(value and value.strip() for value in required):
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="External authentication is not fully configured.",
        )
    try:
        signing_key = _jwks_client(settings.external_auth_jwks_url).get_signing_key_from_jwt(token).key
        claims: dict[str, Any] = jwt.decode(
            token,
            signing_key,
            algorithms=["RS256"],
            issuer=settings.external_auth_issuer,
            audience=settings.external_auth_audience,
            options={"require": ["exp", "iss", "aud", settings.external_auth_subject_claim, settings.external_auth_role_claim]},
        )
        subject = claims.get(settings.external_auth_subject_claim)
        role_value = claims.get(settings.external_auth_role_claim)
        if not isinstance(subject, str) or not subject.strip():
            raise jwt.InvalidTokenError("Missing subject")
        # Only a single explicit role is accepted. Group arrays must be mapped by
        # the organization's IdP before they reach this API; do not guess privilege.
        if not isinstance(role_value, str) or not role_value.strip():
            raise jwt.InvalidTokenError("Missing role")
        return AuthenticatedPrincipal(principal_id=subject.strip(), role=UserRole(role_value.strip().upper()))
    except HTTPException:
        raise
    except Exception as exc:
        # Do not leak token/JWKS details or claim contents to clients.
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired authentication credentials.",
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc


async def get_current_principal(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> AuthenticatedPrincipal:
    """Authenticate caller and return a server-derived principal."""
    settings = get_settings()
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication credentials were not provided.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    if settings.auth_mode == "development_static":
        if settings.app_env not in {"development", "testing"}:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Development authentication is disabled outside development/testing.",
            )
        principal = _parse_development_principal(credentials.credentials, settings)
        if principal is None:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid authentication credentials.",
                headers={"WWW-Authenticate": "Bearer"},
            )
        return principal

    # JWKS retrieval may perform blocking network I/O; keep it off the event loop.
    return await asyncio.to_thread(_verify_external_jwt, credentials.credentials, settings)


def require_role(principal: AuthenticatedPrincipal, *allowed_roles: UserRole) -> None:
    """Raise 403 unless the principal has one of the allowed roles."""
    if principal.role not in set(allowed_roles):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Caller is not authorized for this operation.")


def can_access_request(principal: AuthenticatedPrincipal, submitting_officer_id: str) -> bool:
    """Authorize request detail access under the role model."""
    if principal.role in {UserRole.ADMIN, UserRole.IO}:
        return True
    return principal.role == UserRole.OFFICER and principal.principal_id == submitting_officer_id
