import base64
import re
import uuid
from datetime import datetime
from typing import Annotated, Literal

from pydantic import BaseModel, BeforeValidator, Field, PlainSerializer, field_validator

from .config import settings


def _decode(value):
    if isinstance(value, (bytes, bytearray)):
        return bytes(value)
    if not isinstance(value, str):
        raise ValueError("expected base64 string")
    try:
        return base64.b64decode(value, validate=True)
    except ValueError as exc:
        raise ValueError("invalid base64") from exc


B64 = Annotated[
    bytes,
    BeforeValidator(_decode),
    PlainSerializer(lambda b: base64.b64encode(b).decode(), return_type=str, when_used="json"),
]

# Sealed blob: version byte + 24 byte nonce + 16 byte tag, plus the payload.
OVERHEAD = 1 + 24 + 16
Key32 = Annotated[B64, Field(min_length=32, max_length=32)]
Salt = Annotated[B64, Field(min_length=16, max_length=16)]
WrappedKey = Annotated[B64, Field(min_length=OVERHEAD + 32, max_length=OVERHEAD + 32)]
Blob = Annotated[B64, Field(min_length=OVERHEAD, max_length=settings.max_blob_bytes)]
DeviceName = Annotated[str, Field(min_length=1, max_length=100)]

_EMAIL = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


class EmailIn(BaseModel):
    email: Annotated[str, Field(max_length=320)]

    @field_validator("email")
    @classmethod
    def _email(cls, value: str) -> str:
        value = value.strip().lower()
        if not _EMAIL.match(value):
            raise ValueError("invalid email")
        return value


class KdfParams(BaseModel):
    kdf_salt: Salt
    kdf_ops: int = Field(ge=1, le=20)
    kdf_mem: int = Field(ge=8 * 1024 * 1024, le=1024 * 1024 * 1024)


class PreloginOut(KdfParams):
    pass


class RegisterIn(EmailIn, KdfParams):
    auth_key: Key32
    wrapped_account_key: WrappedKey
    public_key: Key32
    wrapped_private_key: WrappedKey
    recovery_auth: Key32
    recovery_wrapped_key: WrappedKey
    device_name: DeviceName


class LoginIn(EmailIn):
    auth_key: Key32
    device_name: DeviceName


class LoginOut(KdfParams):
    token: str
    session_id: uuid.UUID
    user_id: uuid.UUID
    email: str
    wrapped_account_key: B64
    public_key: B64
    wrapped_private_key: B64


class ChangePasswordIn(KdfParams):
    current_auth_key: Key32
    new_auth_key: Key32
    wrapped_account_key: WrappedKey


class RecoverStartIn(EmailIn):
    recovery_auth: Key32


class RecoverStartOut(BaseModel):
    recovery_wrapped_key: B64


class RecoverFinishIn(EmailIn, KdfParams):
    recovery_auth: Key32
    new_auth_key: Key32
    wrapped_account_key: WrappedKey
    device_name: DeviceName


class SessionOut(BaseModel):
    id: uuid.UUID
    device_name: str
    created_at: datetime
    last_seen_at: datetime
    current: bool


class ItemPut(BaseModel):
    blob: Blob
    base_revision: int | None = None
    wrapped_key: WrappedKey | None = None


class ItemOut(BaseModel):
    id: uuid.UUID
    revision: int
    item_revision: int
    deleted: bool
    owner_id: uuid.UUID | None = None
    blob: B64 | None = None
    permission: str | None = None
    key_kind: str | None = None
    wrapped_key: B64 | None = None
    granted_by: uuid.UUID | None = None
    granted_by_email: str | None = None
    granted_by_public_key: B64 | None = None


class SyncOut(BaseModel):
    revision: int
    items: list[ItemOut]


class UserLookupOut(BaseModel):
    id: uuid.UUID
    email: str
    public_key: B64


class GrantIn(BaseModel):
    user_id: uuid.UUID
    wrapped_key: WrappedKey
    permission: Literal["read", "write"]


class GrantOut(BaseModel):
    user_id: uuid.UUID
    email: str
    public_key: B64
    permission: str
    key_kind: str


class RewrappedKey(BaseModel):
    user_id: uuid.UUID
    wrapped_key: WrappedKey


class RevokeIn(BaseModel):
    user_id: uuid.UUID
    base_revision: int
    blob: Blob
    grants: list[RewrappedKey]
