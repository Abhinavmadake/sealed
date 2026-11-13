import uuid
from datetime import UTC, datetime

from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from fastapi.responses import JSONResponse
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session as DbSession

from ..db import get_db
from ..deps import Auth, current_auth
from ..models import Grant, Item
from ..revisions import next_revision
from ..schemas import ItemOut, ItemPut
from ..views import active_grant, conflict, view_for

router = APIRouter(prefix="/items", tags=["items"])

NOT_FOUND = "item not found"


def _create(item_id: uuid.UUID, body: ItemPut, auth: Auth, db: DbSession):
    if body.wrapped_key is None:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "wrapped_key is required to create")
    revision = next_revision(db)
    item = Item(id=item_id, owner_id=auth.user.id, blob=body.blob, revision=revision)
    grant = Grant(
        item_id=item_id,
        user_id=auth.user.id,
        granted_by=auth.user.id,
        wrapped_key=body.wrapped_key,
        key_kind="self",
        permission="owner",
        revision=revision,
    )
    try:
        db.add(item)
        db.flush()
        db.add(grant)
        db.commit()
    except IntegrityError:
        db.rollback()
        return conflict("item already exists")
    out = view_for(db, item, grant)
    return JSONResponse(status_code=status.HTTP_201_CREATED, content=out.model_dump(mode="json"))


@router.put("/{item_id}", response_model=ItemOut)
def put_item(
    item_id: uuid.UUID, body: ItemPut, auth: Auth = Depends(current_auth), db: DbSession = Depends(get_db)
):
    item = db.get(Item, item_id, with_for_update=True)
    if item is None:
        if body.base_revision is not None:
            raise HTTPException(status.HTTP_404_NOT_FOUND, NOT_FOUND)
        return _create(item_id, body, auth, db)

    grant = active_grant(db, item, auth.user.id)
    if grant is None:
        if body.base_revision is None:
            return conflict("item already exists")
        raise HTTPException(status.HTTP_404_NOT_FOUND, NOT_FOUND)
    current = view_for(db, item, grant)

    if body.base_revision is None:
        if item.deleted_at is None and item.blob == body.blob:
            return current
        return conflict("item already exists", current)
    if grant.permission == "read":
        raise HTTPException(status.HTTP_403_FORBIDDEN, "read-only access")
    if body.wrapped_key is not None:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "wrapped_key is only accepted on create")
    if item.deleted_at is not None or body.base_revision != item.revision:
        return conflict("stale revision", current)

    item.blob = body.blob
    item.revision = next_revision(db)
    item.updated_at = datetime.now(UTC)
    db.commit()
    return view_for(db, item, grant)


@router.delete("/{item_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_item(
    item_id: uuid.UUID,
    base_revision: int = Query(),
    auth: Auth = Depends(current_auth),
    db: DbSession = Depends(get_db),
):
    item = db.get(Item, item_id, with_for_update=True)
    grant = active_grant(db, item, auth.user.id) if item else None
    if grant is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, NOT_FOUND)
    if grant.permission != "owner":
        raise HTTPException(status.HTTP_403_FORBIDDEN, "only the owner can delete")
    if item.deleted_at is None:
        if base_revision != item.revision:
            return conflict("stale revision", view_for(db, item, grant))
        now = datetime.now(UTC)
        item.deleted_at = now
        item.updated_at = now
        item.blob = None
        item.revision = next_revision(db)
        db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
