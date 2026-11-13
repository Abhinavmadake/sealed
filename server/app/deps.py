from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

from fastapi import Depends, Header, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session as DbSession

from .db import get_db
from .models import Session, User
from .security import hash_token


@dataclass
class Auth:
    user: User
    session: Session


def current_auth(
    authorization: str | None = Header(default=None),
    db: DbSession = Depends(get_db),
) -> Auth:
    unauthorized = HTTPException(status.HTTP_401_UNAUTHORIZED, "not signed in")
    if not authorization or not authorization.startswith("Bearer "):
        raise unauthorized
    session = db.scalar(
        select(Session).where(Session.token_hash == hash_token(authorization[7:].strip()))
    )
    now = datetime.now(UTC)
    if session is None or session.expires_at <= now:
        raise unauthorized
    if now - session.last_seen_at > timedelta(minutes=1):
        session.last_seen_at = now
        db.commit()
    user = db.get(User, session.user_id)
    return Auth(user=user, session=session)
