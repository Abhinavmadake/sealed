from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="SEALED_", env_file=".env", extra="ignore")

    database_url: str = "postgresql+psycopg:///sealed"
    server_secret: str = "dev-only-change-me"
    session_days: int = 30
    max_failures: int = 5
    lockout_minutes: int = 15
    max_blob_bytes: int = 64 * 1024
    min_kdf_ops: int = 3
    min_kdf_mem: int = 64 * 1024 * 1024
    default_kdf_ops: int = 3
    default_kdf_mem: int = 256 * 1024 * 1024
    hash_time_cost: int = 2
    hash_memory_kib: int = 19 * 1024
    cors_origins: list[str] = ["*"]


settings = Settings()
