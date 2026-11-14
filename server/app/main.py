from fastapi import APIRouter, FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .config import settings
from .routers import auth, items, sessions, sharing, sync

app = FastAPI(title="Sealed", version="1.0.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_methods=["*"],
    allow_headers=["Authorization", "Content-Type", "ngrok-skip-browser-warning"],
)

api = APIRouter(prefix="/api/v1")
api.include_router(auth.router)
api.include_router(sessions.router)
api.include_router(items.router)
api.include_router(sync.router)
api.include_router(sharing.router)


@api.get("/health", tags=["meta"])
def health():
    return {"status": "ok"}


app.include_router(api)
