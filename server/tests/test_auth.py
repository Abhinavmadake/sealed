import base64

from sqlalchemy import text

from app.config import settings
from app.db import engine

from .conftest import WRAPPED, b64, rand

API = "/api/v1"


def bearer(token):
    return {"Authorization": f"Bearer {token}"}


def login(client, email, auth_key, device="phone"):
    return client.post(f"{API}/auth/login", json={"email": email, "auth_key": auth_key, "device_name": device})


def test_register_and_login(client, make_account):
    alice = make_account()
    assert alice.login["email"] == "alice@example.com"
    r = login(client, "alice@example.com", alice.auth_key)
    assert r.status_code == 200
    assert r.json()["wrapped_account_key"] == alice.register_body["wrapped_account_key"]


def test_wrong_auth_key_rejected(client, make_account):
    make_account()
    r = login(client, "alice@example.com", rand(32))
    assert r.status_code == 401
    assert r.json()["detail"] == "invalid email or password"


def test_unknown_email_same_error(client):
    r = login(client, "nobody@example.com", rand(32))
    assert r.status_code == 401
    assert r.json()["detail"] == "invalid email or password"


def test_email_is_case_insensitive(client, make_account):
    alice = make_account("Alice@Example.com")
    assert alice.login["email"] == "alice@example.com"
    assert login(client, "ALICE@example.COM", alice.auth_key).status_code == 200


def test_duplicate_email_rejected(client, make_account):
    alice = make_account()
    r = client.post(f"{API}/auth/register", json=alice.register_body)
    assert r.status_code == 409


def test_prelogin_returns_real_params(client, make_account):
    alice = make_account()
    r = client.post(f"{API}/auth/prelogin", json={"email": "alice@example.com"})
    assert r.json()["kdf_salt"] == alice.register_body["kdf_salt"]


def test_prelogin_fakes_unknown_emails(client):
    a = client.post(f"{API}/auth/prelogin", json={"email": "ghost@example.com"}).json()
    b = client.post(f"{API}/auth/prelogin", json={"email": "ghost@example.com"}).json()
    c = client.post(f"{API}/auth/prelogin", json={"email": "other@example.com"}).json()
    assert a == b
    assert a["kdf_salt"] != c["kdf_salt"]
    assert len(base64.b64decode(a["kdf_salt"])) == 16
    assert a["kdf_ops"] == settings.default_kdf_ops


def test_weak_kdf_rejected(client, make_account):
    alice = make_account()
    body = dict(alice.register_body, email="bob@example.com", kdf_mem=8 * 1024 * 1024)
    assert client.post(f"{API}/auth/register", json=body).status_code == 422


def test_bad_key_lengths_rejected(client, make_account):
    alice = make_account()
    for field, value in [("auth_key", rand(31)), ("kdf_salt", rand(8)), ("wrapped_account_key", rand(WRAPPED - 1)), ("public_key", "not base64!")]:
        body = dict(alice.register_body, email="bob@example.com", **{field: value})
        assert client.post(f"{API}/auth/register", json=body).status_code == 422, field


def test_lockout_after_repeated_failures(client, make_account):
    alice = make_account()
    for _ in range(settings.max_failures):
        assert login(client, alice.email, rand(32)).status_code == 401
    r = login(client, alice.email, alice.auth_key)
    assert r.status_code == 429
    assert int(r.headers["Retry-After"]) > 0


def test_success_resets_failure_count(client, make_account):
    alice = make_account()
    for _ in range(settings.max_failures - 1):
        login(client, alice.email, rand(32))
    assert login(client, alice.email, alice.auth_key).status_code == 200
    for _ in range(settings.max_failures - 1):
        login(client, alice.email, rand(32))
    assert login(client, alice.email, alice.auth_key).status_code == 200


def test_requests_need_a_valid_token(client):
    assert client.get(f"{API}/sessions").status_code == 401
    assert client.get(f"{API}/sessions", headers=bearer("made-up")).status_code == 401


def test_logout_ends_session(client, make_account):
    alice = make_account()
    assert alice.post("/auth/logout").status_code == 204
    assert alice.get("/sessions").status_code == 401


def test_session_list_and_remote_signout(client, make_account):
    alice = make_account()
    other = alice.new_session("laptop")
    sessions = alice.get("/sessions").json()
    assert len(sessions) == 2
    current = [s for s in sessions if s["current"]]
    assert len(current) == 1 and current[0]["device_name"] == "test phone"
    laptop = next(s for s in sessions if s["device_name"] == "laptop")
    assert alice.delete(f"/sessions/{laptop['id']}").status_code == 204
    assert client.get(f"{API}/sessions", headers=bearer(other)).status_code == 401
    assert alice.get("/sessions").status_code == 200


def test_cannot_end_someone_elses_session(client, make_account):
    alice = make_account()
    bob = make_account("bob@example.com")
    bob_session = bob.get("/sessions").json()[0]["id"]
    assert alice.delete(f"/sessions/{bob_session}").status_code == 404


def _change_body(current, new):
    return {
        "current_auth_key": current,
        "new_auth_key": new,
        "kdf_salt": rand(16),
        "kdf_ops": 3,
        "kdf_mem": 256 * 1024 * 1024,
        "wrapped_account_key": rand(WRAPPED),
    }


def test_change_password(client, make_account):
    alice = make_account()
    other = alice.new_session()
    new_key = rand(32)
    body = _change_body(alice.auth_key, new_key)
    assert alice.post("/auth/change-password", json=body).status_code == 204
    assert login(client, alice.email, alice.auth_key).status_code == 401
    r = login(client, alice.email, new_key)
    assert r.status_code == 200
    assert r.json()["wrapped_account_key"] == body["wrapped_account_key"]
    assert r.json()["kdf_salt"] == body["kdf_salt"]
    assert client.get(f"{API}/sessions", headers=bearer(other)).status_code == 401
    assert alice.get("/sessions").status_code == 200


def test_change_password_needs_current(make_account):
    alice = make_account()
    assert alice.post("/auth/change-password", json=_change_body(rand(32), rand(32))).status_code == 401


def test_recovery(client, make_account):
    alice = make_account()
    bad = client.post(f"{API}/auth/recover/start", json={"email": alice.email, "recovery_auth": rand(32)})
    assert bad.status_code == 401
    r = client.post(f"{API}/auth/recover/start", json={"email": alice.email, "recovery_auth": alice.recovery_auth})
    assert r.status_code == 200
    assert r.json()["recovery_wrapped_key"] == alice.register_body["recovery_wrapped_key"]
    new_key = rand(32)
    finish = {
        "email": alice.email,
        "recovery_auth": alice.recovery_auth,
        "new_auth_key": new_key,
        "kdf_salt": rand(16),
        "kdf_ops": 3,
        "kdf_mem": 256 * 1024 * 1024,
        "wrapped_account_key": rand(WRAPPED),
        "device_name": "new phone",
    }
    r = client.post(f"{API}/auth/recover/finish", json=finish)
    assert r.status_code == 200
    assert alice.get("/sessions").status_code == 401
    assert login(client, alice.email, new_key).status_code == 200


def test_server_stores_no_raw_secrets(make_account):
    alice = make_account()
    raw_auth = base64.b64decode(alice.auth_key)
    raw_recovery = base64.b64decode(alice.recovery_auth)
    with engine.connect() as conn:
        row = conn.execute(text("SELECT * FROM users")).mappings().one()
        token_hash = conn.execute(text("SELECT token_hash FROM sessions")).scalar_one()
    assert row["auth_hash"].startswith("$argon2id$")
    assert row["recovery_auth_hash"].startswith("$argon2id$")
    for value in row.values():
        as_bytes = value if isinstance(value, bytes) else str(value).encode()
        assert raw_auth not in as_bytes and b64(raw_auth).encode() not in as_bytes
        assert raw_recovery not in as_bytes
    assert alice.token.encode() != token_hash
