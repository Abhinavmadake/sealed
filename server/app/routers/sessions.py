import uuid

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy import select
from sqlalchemy.orm import Session as DbSession

from ..db import get_db
from ..deps import Auth, current_auth
from ..models import Session
from ..schemas import SessionOut

router = APIRouter(prefix="/sessions", tags=["sessions"])


@router.get("", response_model=list[SessionOut])
def list_sessions(auth: Auth = Depends(current_auth), db: DbSession = Depends(get_db)):
    rows = db.scalars(
        select(Session).where(Session.user_id == auth.user.id).order_by(Session.last_seen_at.desc())
    )
    return [
        SessionOut(
            id=s.id,
            device_name=s.device_name,
            created_at=s.created_at,
            last_seen_at=s.last_seen_at,
            current=s.id == auth.session.id,
        )
        for s in rows
    ]


@router.delete("/{session_id}", status_code=status.HTTP_204_NO_CONTENT)
def end_session(
    session_id: uuid.UUID, auth: Auth = Depends(current_auth), db: DbSession = Depends(get_db)
):
    session = db.get(Session, session_id)
    if session is None or session.user_id != auth.user.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "session not found")
    db.delete(session)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
