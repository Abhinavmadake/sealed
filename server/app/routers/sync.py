from fastapi import APIRouter, Depends, Query
from sqlalchemy import or_, select
from sqlalchemy.orm import Session as DbSession

from ..db import get_db
from ..deps import Auth, current_auth
from ..models import Grant, Item, User
from ..revisions import current_revision
from ..schemas import SyncOut
from ..views import item_view

router = APIRouter(tags=["sync"])


@router.get("/sync", response_model=SyncOut)
def sync(
    since: int = Query(0, ge=0), auth: Auth = Depends(current_auth), db: DbSession = Depends(get_db)
):
    # Read the cursor first: anything committed after this is re-sent next time, never skipped.
    revision = current_revision(db)
    query = (
        select(Item, Grant, User)
        .join(Grant, Grant.item_id == Item.id)
        .join(User, User.id == Grant.granted_by)
        .where(Grant.user_id == auth.user.id)
    )
    if since == 0:
        query = query.where(Item.deleted_at.is_(None), Grant.revoked_at.is_(None))
    else:
        query = query.where(or_(Item.revision > since, Grant.revision > since))
    items = sorted((item_view(*row) for row in db.execute(query)), key=lambda i: i.revision)
    return SyncOut(revision=revision, items=items)
