#!/usr/bin/env python3
"""A second Sealed client in Python, written against the documented formats only.

It shares no code with the Flutter app, so reading the same vault with it shows the
key hierarchy and blob format are what docs/PLAN.md says they are.

    second_device.py EMAIL PASSWORD list
    second_device.py EMAIL PASSWORD set TITLE FIELD VALUE
    second_device.py EMAIL PASSWORD raw
    second_device.py EMAIL PASSWORD logout
"""
import base64
import datetime
import hashlib
import json
import os
import sys

import httpx
from nacl import bindings, pwhash

API = os.environ.get("SEALED_SERVER", "http://127.0.0.1:8000") + "/api/v1"
DEVICE = "Laptop (script)"
PAD_BLOCK = 256


def b64(data: bytes) -> str:
    return base64.b64encode(data).decode()


def subkey(master: bytes, key_id: int) -> bytes:
    # libsodium crypto_kdf: BLAKE2b keyed with the master key, id as salt, context as personal.
    return hashlib.blake2b(
        digest_size=32, key=master, salt=key_id.to_bytes(8, "little"), person=b"sealedv1"
    ).digest()


def open_blob(key: bytes, blob: bytes, label: str) -> bytes:
    if blob[0] != 1:
        raise ValueError("unknown blob version")
    return bindings.crypto_aead_xchacha20poly1305_ietf_decrypt(blob[25:], label.encode(), blob[1:25], key)


def seal_blob(key: bytes, message: bytes, label: str) -> bytes:
    nonce = os.urandom(24)
    return b"\x01" + nonce + bindings.crypto_aead_xchacha20poly1305_ietf_encrypt(
        message, label.encode(), nonce, key
    )


def pad(data: bytes) -> bytes:
    data += b"\x80"
    return data + b"\0" * (-len(data) % PAD_BLOCK)


def unpad(data: bytes) -> bytes:
    return data.rstrip(b"\0")[:-1]


class Device:
    def __init__(self, email: str, password: str):
        self.http = httpx.Client(base_url=API, timeout=30)
        self.cache = os.path.join(os.path.dirname(os.path.abspath(__file__)), f".session-{email}.json")
        pre = self.http.post("/auth/prelogin", json={"email": email}).json()
        master = pwhash.argon2id.kdf(
            32, password.encode(), base64.b64decode(pre["kdf_salt"]), pre["kdf_ops"], pre["kdf_mem"]
        )
        auth_key, wrap_key = subkey(master, 1), subkey(master, 2)
        login = self._cached() or self._login(email, auth_key)
        self.account_key = open_blob(wrap_key, base64.b64decode(login["wrapped_account_key"]), "sealed.account.v1")
        self.private_key = open_blob(
            self.account_key, base64.b64decode(login["wrapped_private_key"]), "sealed.private.v1"
        )

    def _cached(self):
        if not os.path.exists(self.cache):
            return None
        with open(self.cache) as f:
            login = json.load(f)
        self.http.headers["Authorization"] = "Bearer " + login["token"]
        return login if self.http.get("/sessions").status_code == 200 else None

    def _login(self, email: str, auth_key: bytes):
        r = self.http.post("/auth/login", json={"email": email, "auth_key": b64(auth_key), "device_name": DEVICE})
        if r.status_code != 200:
            sys.exit(f"login failed: {r.status_code} {r.text}")
        login = r.json()
        with open(self.cache, "w") as f:
            json.dump(login, f)
        self.http.headers["Authorization"] = "Bearer " + login["token"]
        return login

    def raw(self):
        return self.http.get("/sync", params={"since": 0}).json()["items"]

    def item_key(self, item) -> bytes:
        wrapped = base64.b64decode(item["wrapped_key"])
        if item["key_kind"] == "self":
            return open_blob(self.account_key, wrapped, "sealed.itemkey.v1:" + item["id"])
        sender = base64.b64decode(item["granted_by_public_key"])
        return bindings.crypto_box_open(wrapped[25:], wrapped[1:25], sender, self.private_key)

    def items(self):
        for item in self.raw():
            key = self.item_key(item)
            data = json.loads(unpad(open_blob(key, base64.b64decode(item["blob"]), "sealed.item.v1:" + item["id"])))
            yield item, key, data

    def set(self, title: str, field: str, value: str):
        for item, key, data in self.items():
            if data["title"] != title:
                continue
            data[field] = value
            data["modified"] = datetime.datetime.now(datetime.UTC).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
            blob = seal_blob(key, pad(json.dumps(data).encode()), "sealed.item.v1:" + item["id"])
            r = self.http.put(
                "/items/" + item["id"], json={"blob": b64(blob), "base_revision": item["item_revision"]}
            )
            print(r.status_code, "revision", r.json().get("item_revision", r.text))
            return
        sys.exit(f'no item titled "{title}"')

    def logout(self):
        print(self.http.post("/auth/logout").status_code)
        os.remove(self.cache)


def main():
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    email, password, command, *args = sys.argv[1:]
    device = Device(email, password)
    if command == "list":
        for item, _, data in device.items():
            print(f"rev {item['item_revision']:>4}  {item['permission']:<5}  {json.dumps(data)}")
    elif command == "raw":
        for item in device.raw():
            print(f"{item['id']}  rev {item['item_revision']}  {item['blob'][:60]}...")
    elif command == "set" and len(args) == 3:
        device.set(*args)
    elif command == "logout":
        device.logout()
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
