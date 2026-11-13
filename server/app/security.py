import hashlib
import hmac
import secrets

from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError

from .config import settings

SALT_BYTES = 16

_hasher = PasswordHasher(
    time_cost=settings.hash_time_cost, memory_cost=settings.hash_memory_kib, parallelism=1
)
_dummy_hash = _hasher.hash(b"\0" * 32)


def hash_secret(secret: bytes) -> str:
    return _hasher.hash(secret)


def verify_secret(stored: str | None, secret: bytes) -> bool:
    try:
        return _hasher.verify(stored or _dummy_hash, secret) and stored is not None
    except (VerificationError, InvalidHashError):
        return False


def new_token() -> str:
    return secrets.token_urlsafe(32)


def hash_token(token: str) -> bytes:
    return hashlib.sha256(token.encode()).digest()


def fake_salt(email: str) -> bytes:
    key = settings.server_secret.encode()
    return hmac.new(key, b"salt:" + email.encode(), hashlib.sha256).digest()[:SALT_BYTES]


def normalize_email(email: str) -> str:
    return email.strip().lower()
