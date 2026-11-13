from sqlalchemy import text
from sqlalchemy.orm import Session


def next_revision(db: Session) -> int:
    return db.execute(
        text("UPDATE sync_counter SET value = value + 1 WHERE id = 1 RETURNING value")
    ).scalar_one()


def current_revision(db: Session) -> int:
    return db.execute(text("SELECT value FROM sync_counter WHERE id = 1")).scalar_one()
