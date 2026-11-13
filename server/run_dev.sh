#!/bin/sh
# Starts Postgres if needed, applies migrations, and serves the API on port 8000.
set -e
cd "$(dirname "$0")"
PG=/opt/homebrew/opt/postgresql@17/bin
DATA=/opt/homebrew/var/postgresql@17
"$PG/pg_ctl" -D "$DATA" status >/dev/null 2>&1 || "$PG/pg_ctl" -D "$DATA" -l "$DATA/server.log" -w start
.venv/bin/alembic upgrade head
exec .venv/bin/uvicorn app.main:app --host "${HOST:-127.0.0.1}" --port "${PORT:-8000}"
