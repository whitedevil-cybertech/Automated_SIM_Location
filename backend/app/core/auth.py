"""Authentication and authorization helpers.

Phase 2 does not include a production identity-provider integration. This module
therefore makes the boundary explicit: production/staging must use an external
provider, while development/testing may use isolated static bearer tokens.
"""

from dataclasses import dataclass
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


def _parse_development_principal(
    token: str,
    settings: Settings,
) -> AuthenticatedPrincipal | None:
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


async def get_current_principal(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> AuthenticatedPrincipal:
    """Authenticate request and return a server-derived principal.

    The development token path is deliberately disabled outside development and
    testing so it cannot silently become production authentication.
    """
    settings = get_settings()
    if settings.auth_mode == "development_static":
        if settings.app_env not in {"development", "testing"}:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Production authentication provider is not configured.",
            )
        if credentials is None or credentials.scheme.lower() != "bearer":
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Authentication credentials were not provided.",
            )
        principal = _parse_development_principal(credentials.credentials, settings)
        if principal is None:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid authentication credentials.",
            )
        return principal

    raise HTTPException(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        detail="External authentication provider integration is required.",
    )


def require_role(
    principal: AuthenticatedPrincipal,
    *allowed_roles: UserRole,
) -> None:
    """Raise 403 unless the principal has one of the allowed roles."""
    if principal.role not in set(allowed_roles):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Caller is not authorized for this operation.",
        )


def can_access_request(
    principal: AuthenticatedPrincipal,
    submitting_officer_id: str,
) -> bool:
    """Authorize request detail access under the Phase 2 role model."""
    if principal.role in {UserRole.ADMIN, UserRole.IO}:
        return True
    return (
        principal.role == UserRole.OFFICER
        and principal.principal_id == submitting_officer_id
    )
