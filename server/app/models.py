import uuid
from datetime import datetime

from sqlalchemy import (
    BigInteger, CheckConstraint, DateTime, ForeignKey, Integer, LargeBinary, String, func,
)
from sqlalchemy.orm import Mapped, mapped_column

from .db import Base


def _now():
    return mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)


class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    email: Mapped[str] = mapped_column(String(320), unique=True)
    auth_hash: Mapped[str] = mapped_column(String(200))
    kdf_salt: Mapped[bytes] = mapped_column(LargeBinary)
    kdf_ops: Mapped[int] = mapped_column(Integer)
    kdf_mem: Mapped[int] = mapped_column(BigInteger)
    wrapped_account_key: Mapped[bytes] = mapped_column(LargeBinary)
    public_key: Mapped[bytes] = mapped_column(LargeBinary)
    wrapped_private_key: Mapped[bytes] = mapped_column(LargeBinary)
    recovery_auth_hash: Mapped[str] = mapped_column(String(200))
    recovery_wrapped_key: Mapped[bytes] = mapped_column(LargeBinary)
    created_at: Mapped[datetime] = _now()


class Session(Base):
    __tablename__ = "sessions"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    token_hash: Mapped[bytes] = mapped_column(LargeBinary, unique=True)
    device_name: Mapped[str] = mapped_column(String(100))
    created_at: Mapped[datetime] = _now()
    last_seen_at: Mapped[datetime] = _now()
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class Item(Base):
    __tablename__ = "items"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True)
    owner_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    blob: Mapped[bytes | None] = mapped_column(LargeBinary)
    revision: Mapped[int] = mapped_column(BigInteger, index=True)
    created_at: Mapped[datetime] = _now()
    updated_at: Mapped[datetime] = _now()
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class Grant(Base):
    __tablename__ = "grants"
    __table_args__ = (
        CheckConstraint("key_kind IN ('self', 'box')", name="key_kind"),
        CheckConstraint("permission IN ('owner', 'write', 'read')", name="permission"),
    )

    item_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("items.id", ondelete="CASCADE"), primary_key=True)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True, index=True)
    granted_by: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    wrapped_key: Mapped[bytes] = mapped_column(LargeBinary)
    key_kind: Mapped[str] = mapped_column(String(8))
    permission: Mapped[str] = mapped_column(String(8))
    revision: Mapped[int] = mapped_column(BigInteger, index=True)
    created_at: Mapped[datetime] = _now()
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class LoginAttempt(Base):
    __tablename__ = "login_attempts"

    email: Mapped[str] = mapped_column(String(320), primary_key=True)
    failures: Mapped[int] = mapped_column(Integer, default=0)
    locked_until: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class SyncCounter(Base):
    __tablename__ = "sync_counter"
    __table_args__ = (CheckConstraint("id = 1", name="single_row"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    value: Mapped[int] = mapped_column(BigInteger)
