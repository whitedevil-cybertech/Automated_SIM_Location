"""Application-layer field encryption for sensitive MongoDB values."""

from base64 import urlsafe_b64encode
import hashlib

from cryptography.fernet import Fernet, InvalidToken

from backend.app.core.config import Settings, get_settings
from backend.app.core.exceptions import IFSOException


class SensitiveDataProtectionError(IFSOException):
    """Raised when sensitive field protection cannot be performed safely."""

    def __init__(self, message: str = "Sensitive data protection is unavailable."):
        super().__init__(
            message=message,
            code="SENSITIVE_DATA_PROTECTION_UNAVAILABLE",
            status_code=503,
        )


def _derive_development_key(secret_key: str) -> bytes:
    digest = hashlib.sha256(secret_key.encode("utf-8")).digest()
    return urlsafe_b64encode(digest)


def get_field_fernet(settings: Settings | None = None) -> Fernet:
    """Return a Fernet instance, failing safely when required keying is absent."""
    cfg = settings or get_settings()
    configured_key = cfg.field_encryption_key

    if configured_key:
        try:
            return Fernet(configured_key.encode("utf-8"))
        except (ValueError, TypeError) as exc:
            raise SensitiveDataProtectionError(
                "Configured field encryption key is invalid."
            ) from exc

    if cfg.app_env in {"development", "testing"}:
        return Fernet(_derive_development_key(cfg.secret_key))

    raise SensitiveDataProtectionError(
        "FIELD_ENCRYPTION_KEY is required outside development/testing."
    )


def encrypt_phone_number(phone_number: str, settings: Settings | None = None) -> str:
    """Encrypt a normalized phone number for MongoDB persistence."""
    return get_field_fernet(settings).encrypt(phone_number.encode("utf-8")).decode("utf-8")


def decrypt_phone_number(ciphertext: str, settings: Settings | None = None) -> str:
    """Decrypt a protected phone number for authorized backend workflows."""
    try:
        return get_field_fernet(settings).decrypt(ciphertext.encode("utf-8")).decode("utf-8")
    except InvalidToken as exc:
        raise SensitiveDataProtectionError(
            "Encrypted phone number could not be decrypted."
        ) from exc
