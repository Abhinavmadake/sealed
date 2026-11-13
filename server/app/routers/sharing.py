import uuid
from datetime import UTC, datetime

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.orm import Session as DbSession

from ..db import get_db
from ..deps import Auth, current_auth
from ..models import Grant, Item, User
from ..revisions import next_revision
from ..security import normalize_email
from ..schemas import GrantIn, GrantOut, ItemOut, RevokeIn, UserLookupOut
from ..views import active_grant, conflict, view_for

router = APIRouter(tags=["sharing"])


@router.get("/users/lookup", response_model=UserLookupOut)
def lookup(email: str = Query(), auth: Auth = Depends(current_auth), db: DbSession = Depends(get_db)):
    user = db.scalar(select(User).where(User.email == normalize_email(email)))
    if user is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "no user with that email")
    return UserLookupOut(id=user.id, email=user.email, public_key=user.public_key)


def _owned_item(db: DbSession, item_id: uuid.UUID, auth: Auth) -> tuple[Item, Grant]:
    item = db.get(Item, item_id, with_for_update=True)
    grant = active_grant(db, item, auth.user.id) if item else None
    if grant is None or item.deleted_at is not None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "item not found")
    if grant.permission != "owner":
        raise HTTPException(status.HTTP_403_FORBIDDEN, "only the owner can manage sharing")
    return item, grant


def _active_grants(db: DbSession, item: Item) -> list[tuple[Grant, User]]:
    return list(
        db.execute(
            select(Grant, User)
            .join(User, User.id == Grant.user_id)
            .where(Grant.item_id == item.id, Grant.revoked_at.is_(None))
            .order_by(User.email)
        ).tuples()
    )


def _grant_out(grant: Grant, user: User) -> GrantOut:
    return GrantOut(
        user_id=user.id,
        email=user.email,
        public_key=user.public_key,
        permission=grant.permission,
        key_kind=grant.key_kind,
    )


@router.get("/items/{item_id}/grants", response_model=list[GrantOut])
def list_grants(item_id: uuid.UUID, auth: Auth = Depends(current_auth), db: DbSession = Depends(get_db)):
    item, _ = _owned_item(db, item_id, auth)
    return [_grant_out(g, u) for g, u in _active_grants(db, item)]


@router.post("/items/{item_id}/grants", response_model=GrantOut, status_code=status.HTTP_201_CREATED)
def add_grant(
    item_id: uuid.UUID, body: GrantIn, auth: Auth = Depends(current_auth), db: DbSession = Depends(get_db)
):
    item, _ = _owned_item(db, item_id, auth)
    if body.user_id == auth.user.id:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "cannot share with yourself")
    target = db.get(User, body.user_id)
    if target is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "user not found")
    grant = db.get(Grant, (item.id, target.id))
    if grant is not None and grant.revoked_at is None:
        raise HTTPException(status.HTTP_409_CONFLICT, "already shared with this user")
    if grant is None:
        grant = Grant(item_id=item.id, user_id=target.id)
        db.add(grant)
    grant.granted_by = auth.user.id
    grant.wrapped_key = body.wrapped_key
    grant.key_kind = "box"
    grant.permission = body.permission
    grant.revoked_at = None
    grant.revision = next_revision(db)
    db.commit()
    return _grant_out(grant, target)


@router.post("/items/{item_id}/revoke", response_model=ItemOut)
def revoke(
    item_id: uuid.UUID, body: RevokeIn, auth: Auth = Depends(current_auth), db: DbSession = Depends(get_db)
):
    item, own = _owned_item(db, item_id, auth)
    if body.user_id == auth.user.id:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "cannot revoke your own access")
    grants = {g.user_id: g for g, _ in _active_grants(db, item)}
    target = grants.pop(body.user_id, None)
    if target is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "item is not shared with that user")
    if body.base_revision != item.revision:
        return conflict("stale revision", view_for(db, item, own))
    rewrapped = {k.user_id: k.wrapped_key for k in body.grants}
    if len(rewrapped) != len(body.grants) or rewrapped.keys() != grants.keys():
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_CONTENT, "new keys must cover exactly the remaining users"
        )

    revision = next_revision(db)
    now = datetime.now(UTC)
    target.revoked_at = now
    target.revision = revision
    item.blob = body.blob
    item.revision = revision
    item.updated_at = now
    for user_id, grant in grants.items():
        grant.wrapped_key = rewrapped[user_id]
        grant.granted_by = auth.user.id
        grant.revision = revision
    db.commit()
    return view_for(db, item, own)
