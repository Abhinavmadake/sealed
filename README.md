# Sealed

A zero-knowledge password manager. The server only ever stores ciphertext: all encryption and
decryption happens on the device, so a full database leak reveals no passwords.

- `app/`: Flutter client (Android and web)
- `server/`: FastAPI backend with PostgreSQL
- `docs/PLAN.md`: scope, architecture, key hierarchy, API and known limits

## Features

- Register, log in, lock and unlock (unlock works offline)
- Encrypted vault with logins and secure notes
- Sync across devices with offline editing and field-level conflict merging
- Share an item with another user, revoke with key rotation
- Change the master password, recover with a recovery key
- Password generator and vault health (weak, reused, breached)
- Device list with remote sign-out, auto-lock, clipboard auto-clear

## Requirements

- Flutter (Dart SDK 3.12 or newer) and an Android emulator or Chrome
- Python 3.13
- PostgreSQL 17 (`brew install postgresql@17`)

## Run the server

```sh
cd server
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
/opt/homebrew/opt/postgresql@17/bin/createdb sealed
./run_dev.sh
```

`run_dev.sh` starts Postgres if needed, applies migrations and serves the API on
`http://127.0.0.1:8000`. Interactive API docs are at `/docs`.

Settings come from environment variables with the `SEALED_` prefix or a `server/.env` file
(see `server/app/config.py`). Set `SEALED_SERVER_SECRET` to a random value outside development.

## Run the app

```sh
cd app
flutter pub get
flutter run                 # Android emulator, talks to http://10.0.2.2:8000
flutter run -d chrome       # web, talks to http://localhost:8000
```

To use a different server, pass `--dart-define=SEALED_SERVER=http://host:8000`.

The web build needs the libsodium script once:

```sh
NIX_SKIP_SODIUM_BUILD_HOOKS=1 dart run sodium:update_web --sumo
```

## Tests

```sh
# server, needs a database named sealed_test
cd server
/opt/homebrew/opt/postgresql@17/bin/createdb sealed_test
.venv/bin/pytest

# app, needs the server running and an Android emulator
cd app
tool/test.sh
```

`tool/test.sh` runs the host tests (merge, local store, health) and then the device tests
(real libsodium and sync against the live server).
