import os

os.environ["SEALED_DATABASE_URL"] = "postgresql+psycopg:///sealed_test"
os.environ["SEALED_HASH_MEMORY_KIB"] = "1024"
os.environ["SEALED_HASH_TIME_COST"] = "1"

import base64
import secrets
from pathlib import Path

import pytest
from alembic import command
from alembic.config import Config
from fastapi.testclient import TestClient
from sqlalchemy import text

from app.db import engine
from app.main import app

ROOT = Path(__file__).resolve().parents[1]
WRAPPED = 1 + 24 + 16 + 32


@pytest.fixture(scope="session", autouse=True)
def schema():
    with engine.begin() as conn:
        conn.execute(text("DROP SCHEMA public CASCADE; CREATE SCHEMA public"))
    cfg = Config(str(ROOT / "alembic.ini"))
    cfg.set_main_option("script_location", str(ROOT / "migrations"))
    with engine.begin() as conn:
        cfg.attributes["connection"] = conn
        command.upgrade(cfg, "head")
    yield


@pytest.fixture(autouse=True)
def clean():
    with engine.begin() as conn:
        conn.execute(text("TRUNCATE users, sessions, items, grants, login_attempts CASCADE"))
        conn.execute(text("UPDATE sync_counter SET value = 0"))
    yield


@pytest.fixture
def client():
    return TestClient(app)


def b64(data: bytes) -> str:
    return base64.b64encode(data).decode()


def rand(n: int) -> str:
    return b64(secrets.token_bytes(n))


class Account:
    def __init__(self, client: TestClient, email: str):
        self.client = client
        self.email = email
        self.auth_key = rand(32)
        self.recovery_auth = rand(32)
        self.public_key = rand(32)
        body = {
            "email": email,
            "auth_key": self.auth_key,
            "kdf_salt": rand(16),
            "kdf_ops": 3,
            "kdf_mem": 256 * 1024 * 1024,
            "wrapped_account_key": rand(WRAPPED),
            "public_key": self.public_key,
            "wrapped_private_key": rand(WRAPPED),
            "recovery_auth": self.recovery_auth,
            "recovery_wrapped_key": rand(WRAPPED),
            "device_name": "test phone",
        }
        self.register_body = body
        r = client.post("/api/v1/auth/register", json=body)
        assert r.status_code == 201, r.text
        self.login = r.json()
        self.id = self.login["user_id"]
        self.token = self.login["token"]

    @property
    def headers(self):
        return {"Authorization": f"Bearer {self.token}"}

    def new_session(self, device="second phone") -> str:
        r = self.client.post(
            "/api/v1/auth/login",
            json={"email": self.email, "auth_key": self.auth_key, "device_name": device},
        )
        assert r.status_code == 200, r.text
        return r.json()["token"]

    def get(self, path, **kw):
        return self.client.get("/api/v1" + path, headers=self.headers, **kw)

    def post(self, path, **kw):
        return self.client.post("/api/v1" + path, headers=self.headers, **kw)

    def put(self, path, **kw):
        return self.client.put("/api/v1" + path, headers=self.headers, **kw)

    def delete(self, path, **kw):
        return self.client.delete("/api/v1" + path, headers=self.headers, **kw)


@pytest.fixture
def make_account(client):
    return lambda email="alice@example.com": Account(client, email)
