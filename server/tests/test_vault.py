import threading
import uuid

from sqlalchemy import text

from app.config import settings
from app.db import SessionLocal, engine
from app.revisions import next_revision

from .conftest import WRAPPED, rand


def blob(size=200):
    return rand(size)


def create(account, item_id=None, body=None):
    item_id = item_id or str(uuid.uuid4())
    body = body or {"blob": blob(), "wrapped_key": rand(WRAPPED)}
    r = account.put(f"/items/{item_id}", json=body)
    return item_id, r


def update(account, item_id, base, new_blob=None):
    return account.put(f"/items/{item_id}", json={"blob": new_blob or blob(), "base_revision": base})


def share(owner, item_id, user, permission="read"):
    return owner.post(
        f"/items/{item_id}/grants",
        json={"user_id": user.id, "wrapped_key": rand(WRAPPED), "permission": permission},
    )


def sync(account, since=0):
    r = account.get("/sync", params={"since": since})
    assert r.status_code == 200, r.text
    return r.json()


def test_create_and_sync(make_account):
    alice = make_account()
    body = {"blob": blob(), "wrapped_key": rand(WRAPPED)}
    item_id, r = create(alice, body=body)
    assert r.status_code == 201
    data = sync(alice)
    assert data["revision"] == 1
    [item] = data["items"]
    assert item["id"] == item_id and item["blob"] == body["blob"]
    assert item["wrapped_key"] == body["wrapped_key"]
    assert (item["permission"], item["key_kind"]) == ("owner", "self")
    assert item["granted_by_public_key"] == alice.public_key
    assert sync(alice, since=1)["items"] == []


def test_create_requires_wrapped_key(make_account):
    alice = make_account()
    _, r = create(alice, body={"blob": blob()})
    assert r.status_code == 422


def test_users_only_see_their_items(make_account):
    alice = make_account()
    bob = make_account("bob@example.com")
    item_id, _ = create(alice)
    assert sync(bob)["items"] == []
    assert update(bob, item_id, 1).status_code == 404


def test_update_with_current_revision(make_account):
    alice = make_account()
    item_id, r = create(alice)
    new_blob = blob()
    r = update(alice, item_id, r.json()["item_revision"], new_blob)
    assert r.status_code == 200
    assert r.json()["item_revision"] == 2 and r.json()["blob"] == new_blob


def test_stale_update_returns_current(make_account):
    alice = make_account()
    item_id, r = create(alice)
    first = update(alice, item_id, 1).json()
    r = update(alice, item_id, 1)
    assert r.status_code == 409
    assert r.json()["current"]["blob"] == first["blob"]
    assert r.json()["current"]["item_revision"] == 2


def test_create_retry_is_idempotent(make_account):
    alice = make_account()
    body = {"blob": blob(), "wrapped_key": rand(WRAPPED)}
    item_id, _ = create(alice, body=body)
    _, again = create(alice, item_id, body)
    assert again.status_code == 200
    _, different = create(alice, item_id, {"blob": blob(), "wrapped_key": rand(WRAPPED)})
    assert different.status_code == 409


def test_cannot_take_over_another_users_item_id(make_account):
    alice = make_account()
    bob = make_account("bob@example.com")
    item_id, _ = create(alice)
    _, r = create(bob, item_id)
    assert r.status_code == 409
    assert "current" not in r.json()


def test_blob_size_limit(make_account):
    alice = make_account()
    _, r = create(alice, body={"blob": rand(settings.max_blob_bytes + 1), "wrapped_key": rand(WRAPPED)})
    assert r.status_code == 422


def test_delete_leaves_tombstone(make_account):
    alice = make_account()
    item_id, _ = create(alice)
    assert alice.delete(f"/items/{item_id}", params={"base_revision": 1}).status_code == 204
    assert sync(alice)["items"] == []
    [tomb] = sync(alice, since=1)["items"]
    assert tomb == {**tomb, "id": item_id, "deleted": True, "blob": None, "wrapped_key": None}
    with engine.connect() as conn:
        assert conn.execute(text("SELECT blob FROM items")).scalar_one() is None
    assert alice.delete(f"/items/{item_id}", params={"base_revision": 1}).status_code == 204
    assert update(alice, item_id, 2).status_code == 409


def test_delete_needs_current_revision(make_account):
    alice = make_account()
    item_id, _ = create(alice)
    update(alice, item_id, 1)
    assert alice.delete(f"/items/{item_id}", params={"base_revision": 1}).status_code == 409


def test_lookup(make_account):
    alice = make_account()
    bob = make_account("bob@example.com")
    r = alice.get("/users/lookup", params={"email": " BOB@example.com "})
    assert r.json() == {"id": bob.id, "email": bob.email, "public_key": bob.public_key}
    assert alice.get("/users/lookup", params={"email": "nobody@example.com"}).status_code == 404
    assert alice.get("/users/lookup", params={"email": "not an email"}).status_code == 404


def test_share_read_only(make_account):
    alice = make_account()
    bob = make_account("bob@example.com")
    item_id, _ = create(alice)
    assert share(alice, item_id, bob).status_code == 201
    [item] = sync(bob)["items"]
    assert item["id"] == item_id
    assert (item["permission"], item["key_kind"]) == ("read", "box")
    assert item["granted_by"] == alice.id
    assert item["granted_by_public_key"] == alice.public_key
    assert update(bob, item_id, 1).status_code == 403
    assert bob.delete(f"/items/{item_id}", params={"base_revision": 1}).status_code == 403


def test_share_write(make_account):
    alice = make_account()
    bob = make_account("bob@example.com")
    item_id, _ = create(alice)
    share(alice, item_id, bob, "write")
    new_blob = blob()
    assert update(bob, item_id, 1, new_blob).status_code == 200
    [item] = sync(alice, since=1)["items"]
    assert item["blob"] == new_blob
    assert share(bob, item_id, alice).status_code == 403


def test_share_shows_up_in_incremental_sync(make_account):
    alice = make_account()
    bob = make_account("bob@example.com")
    cursor = sync(bob)["revision"]
    item_id, _ = create(alice)
    share(alice, item_id, bob)
    [item] = sync(bob, since=cursor)["items"]
    assert item["id"] == item_id and not item["deleted"]


def test_share_validation(make_account):
    alice = make_account()
    bob = make_account("bob@example.com")
    item_id, _ = create(alice)
    assert share(alice, item_id, alice).status_code == 422
    assert share(alice, item_id, bob).status_code == 201
    assert share(alice, item_id, bob).status_code == 409
    bad = {"user_id": str(uuid.uuid4()), "wrapped_key": rand(WRAPPED), "permission": "read"}
    assert alice.post(f"/items/{item_id}/grants", json=bad).status_code == 404
    bad = {"user_id": bob.id, "wrapped_key": rand(WRAPPED), "permission": "owner"}
    assert alice.post(f"/items/{item_id}/grants", json=bad).status_code == 422


def test_owner_deleting_hides_item_from_recipients(make_account):
    alice = make_account()
    bob = make_account("bob@example.com")
    item_id, _ = create(alice)
    share(alice, item_id, bob)
    cursor = sync(bob)["revision"]
    alice.delete(f"/items/{item_id}", params={"base_revision": 1})
    [tomb] = sync(bob, since=cursor)["items"]
    assert tomb["deleted"]


def _revoke(owner, item_id, user, base, keys):
    return owner.post(
        f"/items/{item_id}/revoke",
        json={"user_id": user.id, "base_revision": base, "blob": blob(), "grants": keys},
    )


def test_revoke_rotates_key(make_account):
    alice = make_account()
    bob = make_account("bob@example.com")
    carol = make_account("carol@example.com")
    item_id, _ = create(alice)
    share(alice, item_id, bob, "write")
    share(alice, item_id, carol)
    grants = alice.get(f"/items/{item_id}/grants").json()
    assert {g["email"] for g in grants} == {alice.email, bob.email, carol.email}
    cursor = sync(bob)["revision"]

    new_keys = [{"user_id": alice.id, "wrapped_key": rand(WRAPPED)}, {"user_id": carol.id, "wrapped_key": rand(WRAPPED)}]
    r = _revoke(alice, item_id, bob, 1, new_keys)
    assert r.status_code == 200
    assert r.json()["wrapped_key"] == new_keys[0]["wrapped_key"]

    [tomb] = sync(bob, since=cursor)["items"]
    assert tomb["deleted"]
    assert update(bob, item_id, r.json()["item_revision"]).status_code == 404
    [carols] = sync(carol, since=cursor)["items"]
    assert carols["wrapped_key"] == new_keys[1]["wrapped_key"]
    assert carols["blob"] == r.json()["blob"]
    assert {g["email"] for g in alice.get(f"/items/{item_id}/grants").json()} == {alice.email, carol.email}


def test_revoke_must_rewrap_exactly_the_remaining_users(make_account):
    alice = make_account()
    bob = make_account("bob@example.com")
    carol = make_account("carol@example.com")
    item_id, _ = create(alice)
    share(alice, item_id, bob)
    share(alice, item_id, carol)
    me = {"user_id": alice.id, "wrapped_key": rand(WRAPPED)}
    them = {"user_id": carol.id, "wrapped_key": rand(WRAPPED)}
    revoked = {"user_id": bob.id, "wrapped_key": rand(WRAPPED)}
    for keys in ([me], [me, them, revoked], [me, me, them], []):
        assert _revoke(alice, item_id, bob, 1, keys).status_code == 422
    assert _revoke(alice, item_id, bob, 0, [me, them]).status_code == 409
    assert _revoke(alice, item_id, alice, 1, [them]).status_code == 422
    assert _revoke(alice, item_id, bob, 1, [me, them]).status_code == 200
    assert _revoke(alice, item_id, bob, 2, [me, them]).status_code == 404


def test_reshare_after_revoke(make_account):
    alice = make_account()
    bob = make_account("bob@example.com")
    item_id, _ = create(alice)
    share(alice, item_id, bob)
    _revoke(alice, item_id, bob, 1, [{"user_id": alice.id, "wrapped_key": rand(WRAPPED)}])
    assert share(alice, item_id, bob, "write").status_code == 201
    [item] = sync(bob)["items"]
    assert item["permission"] == "write" and not item["deleted"]


def test_revisions_increase_with_every_change(make_account):
    alice = make_account()
    bob = make_account("bob@example.com")
    item_id, _ = create(alice)
    update(alice, item_id, 1)
    share(alice, item_id, bob)
    _revoke(alice, item_id, bob, 2, [{"user_id": alice.id, "wrapped_key": rand(WRAPPED)}])
    assert sync(alice)["revision"] == 4
    assert sync(alice)["items"][0]["revision"] == 4


def test_counter_waits_for_earlier_writer_to_commit():
    first = SessionLocal()
    assert next_revision(first) == 1
    result = {}
    started = threading.Event()

    def second_writer():
        with SessionLocal() as second:
            started.set()
            result["value"] = next_revision(second)
            second.commit()

    worker = threading.Thread(target=second_writer)
    worker.start()
    started.wait()
    worker.join(timeout=0.5)
    assert worker.is_alive(), "second writer should block while the first holds the counter"
    first.commit()
    first.close()
    worker.join(timeout=5)
    assert result["value"] == 2


def test_rolled_back_revision_is_reused():
    with SessionLocal() as db:
        assert next_revision(db) == 1
        db.rollback()
    with SessionLocal() as db:
        assert next_revision(db) == 1
        db.commit()
