from datetime import UTC, datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy import delete, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session as DbSession

from ..config import settings
from ..db import get_db
from ..deps import Auth, current_auth
from ..models import LoginAttempt, Session, User
from ..schemas import (
    ChangePasswordIn, EmailIn, KdfParams, LoginIn, LoginOut, PreloginOut, RecoverFinishIn,
    RecoverStartIn, RecoverStartOut, RegisterIn,
)
from ..security import fake_salt, hash_secret, hash_token, new_token, verify_secret

router = APIRouter(prefix="/auth", tags=["auth"])

BAD_LOGIN = "invalid email or password"


def _check_kdf(params: KdfParams) -> None:
    if params.kdf_ops < settings.min_kdf_ops or params.kdf_mem < settings.min_kdf_mem:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "key derivation too weak")


def _check_lock(db: DbSession, email: str) -> None:
    row = db.get(LoginAttempt, email)
    now = datetime.now(UTC)
    if row and row.locked_until and row.locked_until > now:
        wait = int((row.locked_until - now).total_seconds()) + 1
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS, "too many attempts", headers={"Retry-After": str(wait)}
        )


def _record_failure(db: DbSession, email: str) -> None:
    failures = db.execute(
        insert(LoginAttempt)
        .values(email=email, failures=1)
        .on_conflict_do_update(
            index_elements=[LoginAttempt.email], set_={"failures": LoginAttempt.failures + 1}
        )
        .returning(LoginAttempt.failures)
    ).scalar_one()
    if failures >= settings.max_failures:
        row = db.get(LoginAttempt, email)
        row.failures = 0
        row.locked_until = datetime.now(UTC) + timedelta(minutes=settings.lockout_minutes)
    db.commit()


def _clear_failures(db: DbSession, email: str) -> None:
    db.execute(delete(LoginAttempt).where(LoginAttempt.email == email))


def _new_session(db: DbSession, user: User, device_name: str) -> tuple[str, Session]:
    token = new_token()
    session = Session(
        user_id=user.id,
        token_hash=hash_token(token),
        device_name=device_name,
        expires_at=datetime.now(UTC) + timedelta(days=settings.session_days),
    )
    db.add(session)
    db.flush()
    return token, session


def _login_out(user: User, token: str, session: Session) -> LoginOut:
    return LoginOut(
        token=token,
        session_id=session.id,
        user_id=user.id,
        email=user.email,
        kdf_salt=user.kdf_salt,
        kdf_ops=user.kdf_ops,
        kdf_mem=user.kdf_mem,
        wrapped_account_key=user.wrapped_account_key,
        public_key=user.public_key,
        wrapped_private_key=user.wrapped_private_key,
    )


def _user_by_email(db: DbSession, email: str) -> User | None:
    return db.scalar(select(User).where(User.email == email))


@router.post("/prelogin", response_model=PreloginOut)
def prelogin(body: EmailIn, db: DbSession = Depends(get_db)):
    user = _user_by_email(db, body.email)
    if user is None:
        return PreloginOut(
            kdf_salt=fake_salt(body.email),
            kdf_ops=settings.default_kdf_ops,
            kdf_mem=settings.default_kdf_mem,
        )
    return PreloginOut(kdf_salt=user.kdf_salt, kdf_ops=user.kdf_ops, kdf_mem=user.kdf_mem)


@router.post("/register", response_model=LoginOut, status_code=status.HTTP_201_CREATED)
def register(body: RegisterIn, db: DbSession = Depends(get_db)):
    _check_kdf(body)
    if _user_by_email(db, body.email):
        raise HTTPException(status.HTTP_409_CONFLICT, "email already registered")
    user = User(
        email=body.email,
        auth_hash=hash_secret(body.auth_key),
        kdf_salt=body.kdf_salt,
        kdf_ops=body.kdf_ops,
        kdf_mem=body.kdf_mem,
        wrapped_account_key=body.wrapped_account_key,
        public_key=body.public_key,
        wrapped_private_key=body.wrapped_private_key,
        recovery_auth_hash=hash_secret(body.recovery_auth),
        recovery_wrapped_key=body.recovery_wrapped_key,
    )
    db.add(user)
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        raise HTTPException(status.HTTP_409_CONFLICT, "email already registered")
    token, session = _new_session(db, user, body.device_name)
    db.commit()
    return _login_out(user, token, session)


@router.post("/login", response_model=LoginOut)
def login(body: LoginIn, db: DbSession = Depends(get_db)):
    _check_lock(db, body.email)
    user = _user_by_email(db, body.email)
    if not verify_secret(user.auth_hash if user else None, body.auth_key):
        _record_failure(db, body.email)
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, BAD_LOGIN)
    _clear_failures(db, body.email)
    token, session = _new_session(db, user, body.device_name)
    db.commit()
    return _login_out(user, token, session)


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
def logout(auth: Auth = Depends(current_auth), db: DbSession = Depends(get_db)):
    db.execute(delete(Session).where(Session.id == auth.session.id))
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/change-password", status_code=status.HTTP_204_NO_CONTENT)
def change_password(
    body: ChangePasswordIn, auth: Auth = Depends(current_auth), db: DbSession = Depends(get_db)
):
    _check_kdf(body)
    user = db.get(User, auth.user.id)
    _check_lock(db, user.email)
    if not verify_secret(user.auth_hash, body.current_auth_key):
        _record_failure(db, user.email)
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "current password is wrong")
    user.auth_hash = hash_secret(body.new_auth_key)
    user.kdf_salt = body.kdf_salt
    user.kdf_ops = body.kdf_ops
    user.kdf_mem = body.kdf_mem
    user.wrapped_account_key = body.wrapped_account_key
    db.execute(delete(Session).where(Session.user_id == user.id, Session.id != auth.session.id))
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


def _verify_recovery(db: DbSession, email: str, recovery_auth: bytes) -> User:
    _check_lock(db, email)
    user = _user_by_email(db, email)
    if not verify_secret(user.recovery_auth_hash if user else None, recovery_auth):
        _record_failure(db, email)
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "invalid email or recovery key")
    return user


@router.post("/recover/start", response_model=RecoverStartOut)
def recover_start(body: RecoverStartIn, db: DbSession = Depends(get_db)):
    user = _verify_recovery(db, body.email, body.recovery_auth)
    return RecoverStartOut(recovery_wrapped_key=user.recovery_wrapped_key)


@router.post("/recover/finish", response_model=LoginOut)
def recover_finish(body: RecoverFinishIn, db: DbSession = Depends(get_db)):
    _check_kdf(body)
    user = _verify_recovery(db, body.email, body.recovery_auth)
    _clear_failures(db, body.email)
    user.auth_hash = hash_secret(body.new_auth_key)
    user.kdf_salt = body.kdf_salt
    user.kdf_ops = body.kdf_ops
    user.kdf_mem = body.kdf_mem
    user.wrapped_account_key = body.wrapped_account_key
    db.execute(delete(Session).where(Session.user_id == user.id))
    token, session = _new_session(db, user, body.device_name)
    db.commit()
    return _login_out(user, token, session)
