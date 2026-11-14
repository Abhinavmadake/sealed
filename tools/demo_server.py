"""Serves the API and the built web app from one origin, so a single tunnel can expose both.

    cd server && .venv/bin/uvicorn --app-dir ../tools demo_server:app --port 8000
"""
import sys
from pathlib import Path

from fastapi.staticfiles import StaticFiles

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "server"))

from app.main import app  # noqa: E402

app.mount("/", StaticFiles(directory=ROOT / "app" / "build" / "web", html=True), name="web")
