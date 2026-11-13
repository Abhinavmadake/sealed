from fastapi import status
from fastapi.responses import JSONResponse
from sqlalchemy.orm import Session as DbSession

from .models import Grant, Item, User
from .schemas import ItemOut


def item_view(item: Item, grant: Grant, sharer: User) -> ItemOut:
    revision = max(item.revision, grant.revision)
    if item.deleted_at is not None or grant.revoked_at is not None:
        return ItemOut(id=item.id, revision=revision, item_revision=item.revision, deleted=True)
    return ItemOut(
        id=item.id,
        revision=revision,
        item_revision=item.revision,
        deleted=False,
        owner_id=item.owner_id,
        blob=item.blob,
        permission=grant.permission,
        key_kind=grant.key_kind,
        wrapped_key=grant.wrapped_key,
        granted_by=grant.granted_by,
        granted_by_email=sharer.email,
        granted_by_public_key=sharer.public_key,
    )


def view_for(db: DbSession, item: Item, grant: Grant) -> ItemOut:
    return item_view(item, grant, db.get(User, grant.granted_by))


def active_grant(db: DbSession, item: Item, user_id) -> Grant | None:
    grant = db.get(Grant, (item.id, user_id))
    return grant if grant is not None and grant.revoked_at is None else None


def conflict(message: str, current: ItemOut | None = None) -> JSONResponse:
    body = {"detail": message}
    if current is not None:
        body["current"] = current.model_dump(mode="json")
    return JSONResponse(status_code=status.HTTP_409_CONFLICT, content=body)
