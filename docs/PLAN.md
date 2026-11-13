# Sealed: project plan

Zero-knowledge password manager for the CPAD mini project.
Flutter client, FastAPI backend, PostgreSQL database.

The one rule everything follows: **the server only ever stores ciphertext.** All encryption and
decryption happens on the device. A full database leak reveals email addresses, item counts,
timestamps and who shares with whom. It does not reveal a single password.

## 1. Scope

### In scope
- Register, log in, lock and unlock (unlock works offline)
- Encrypted vault with two item types: login and secure note
- Sync across devices, with offline editing
- Conflict handling: automatic field-level merge, manual choice for real conflicts
- Sharing an item with another user (read or write), revoking with key rotation
- Change master password without re-encrypting items
- Recovery key for a forgotten master password
- Password generator (random and passphrase)
- Vault health: weak, reused and breached passwords
- Session list with remote sign-out
- Auto-lock and clipboard auto-clear
- Biometric unlock on Android

### Out of scope
- Android autofill service (native code, outside the one-framework rule)
- Browser extension, file attachments, teams and organisations
- Email verification, TOTP two-factor login
- Public deployment (runs locally for the demo)

### Platforms
| Platform | Status |
|---|---|
| Android | Primary target, tested on an emulator |
| Web | Second target, tested in Chrome |
| iOS, macOS | Same code. Not built here: Xcode is installed but not selected or licensed, and CocoaPods is missing |

## 2. Architecture

```
Flutter app                                FastAPI server          PostgreSQL
UI -> vault service -> crypto (libsodium)  auth, sessions          users, sessions,
         |                                 items, sync, sharing    items, grants,
         +-> local store (ciphertext only)                         login_attempts,
         +-> sync engine  <--- HTTPS/JSON --->                     sync_counter
```

## 3. Key hierarchy

```
master password + salt
   | Argon2id (ops 3, 256 MiB)
master key (never stored, never sent)
   |-- KDF id 1 -> auth key    sent at login, server stores only its hash
   |-- KDF id 2 -> wrap key    encrypts the account key

account key (random, fixed for the life of the account)
   |-- wraps the user's X25519 private key
   |-- wraps every item key the user holds
   |-- wraps the session token in the local store

item key (random, one per item)
   |-- encrypts the item JSON

recovery key (random, shown once at sign-up)
   |-- KDF id 1 -> recovery auth   server stores only its hash
   |-- KDF id 2 -> recovery wrap   encrypts a second copy of the account key
```

Primitives, all from libsodium: Argon2id, BLAKE2b KDF, XChaCha20-Poly1305 AEAD, X25519 `crypto_box`.

Decisions worth defending:
- **Separate auth key and wrap key.** The server needs proof of the password but must not be able
  to decrypt, so one derived value cannot do both jobs.
- **Account key between password and items.** Changing the password rewraps one key instead of
  re-encrypting the vault.
- **One key per item.** Sharing hands over that item's key and nothing else.
- **Item ID bound in as associated data.** The server cannot swap ciphertext between two items
  without decryption failing.
- **`crypto_box`, not sealed boxes, for sharing.** A sealed box is anonymous, so the server could
  forge a shared item. `crypto_box` proves which user sent it.
- **KDF floor on the client.** A malicious server cannot weaken Argon2 by sending low parameters.
- **Fingerprints for sharing.** The server hands out public keys, so it could substitute its own.
  The app shows a fingerprint both people can compare.

Blob format: `version (1 byte) || nonce (24 bytes) || ciphertext`.

## 4. Database

| Table | Key columns |
|---|---|
| `users` | `id`, `email`, `auth_hash`, `kdf_salt`, `kdf_ops`, `kdf_mem`, `wrapped_account_key`, `public_key`, `wrapped_private_key`, `recovery_auth_hash`, `recovery_wrapped_key` |
| `sessions` | `id`, `user_id`, `token_hash`, `device_name`, `last_seen_at`, `expires_at` |
| `items` | `id` (client UUID), `owner_id`, `blob`, `revision`, `deleted_at` |
| `grants` | `item_id`, `user_id`, `granted_by`, `wrapped_key`, `key_kind`, `permission`, `revision`, `revoked_at` |
| `login_attempts` | `email`, `failures`, `locked_until` |
| `sync_counter` | single row, `value` |

**Sync revisions use a locked counter row, not a Postgres sequence.** Sequence values are handed
out before commit, so a client could read revision 11 while revision 10 is still uncommitted, then
skip 10 forever. Incrementing one row holds its lock until commit, which keeps revisions in commit
order. Throughput is limited, which does not matter at this scale.

## 5. API (`/api/v1`)

| Method and path | Purpose |
|---|---|
| `POST /auth/prelogin` | Salt and KDF parameters (fake but stable for unknown emails) |
| `POST /auth/register` | Create an account from client-generated material |
| `POST /auth/login` | Verify auth key, return token and wrapped keys |
| `POST /auth/logout` | End this session |
| `POST /auth/change-password` | Replace salt, auth hash and wrapped account key, end other sessions |
| `POST /auth/recover/start` | Verify recovery auth, return the recovery-wrapped account key |
| `POST /auth/recover/finish` | Set a new password from the recovered account key |
| `GET /sessions`, `DELETE /sessions/{id}` | List devices, sign one out |
| `GET /sync?since=N` | Everything changed since revision N, including tombstones |
| `PUT /items/{id}` | Create or update, `409` with the current version on a stale `base_revision` |
| `DELETE /items/{id}` | Tombstone an item (owner only) |
| `GET /users/lookup?email=` | Public key for sharing |
| `GET`, `POST /items/{id}/grants` | List and add shares |
| `POST /items/{id}/revoke` | Remove a user and rotate the item key in one transaction |

## 6. Build order

| # | Phase | Done when |
|---|---|---|
| 0 | Prove libsodium works on the device | Done: 1.0.21 on the emulator, Argon2id about 1.2 s |
| 1 | Backend foundation: schema, migrations, auth, sessions | Auth tests pass against real Postgres |
| 2 | Backend vault: items, sync, sharing, revocation | Sync, conflict and permission tests pass |
| 3 | Flutter crypto layer | Round-trip and tamper tests pass |
| 4 | Local store, API client, merge, sync engine | Tests pass against the running server |
| 5 | Core UI: onboarding, unlock, vault, item editing | Full flow works on the emulator |
| 6 | Feature UI: sharing, conflicts, generator, health, devices, recovery | Each feature works on the emulator |
| 7 | End to end: two devices, offline edits, database inspection | Demo script runs start to finish |
| 8 | Project documentation | Report ready to upload |

## 7. Known limits

Stated in the documentation rather than hidden:
- Metadata is visible to the server: emails, timestamps, item sizes, sharing relationships.
- A compromised device or a modified client defeats everything.
- The server could replay an old item version (rollback). Clients do not detect this.
- A revoked user keeps anything they already saw. Rotation only protects future changes.
- Read-only sharing is enforced by the server, not by cryptography.
- Forgetting both the master password and the recovery key loses the vault. That is the cost of
  zero knowledge.
- Dart cannot reliably wipe strings from memory, so decrypted item text can linger until collected.

## 8. File structure

```
sealed/
  README.md
  docs/
    PLAN.md
  server/
    requirements.txt
    alembic.ini
    migrations/             schema history
    app/
      main.py               FastAPI app and router wiring
      config.py             settings from the environment
      db.py                 engine and session
      models.py             SQLAlchemy tables
      schemas.py            request and response shapes
      security.py           hashing, tokens, fake salts
      deps.py               current-user dependency
      revisions.py          locked sync counter
      routers/
        auth.py             prelogin, register, login, password change, recovery
        sessions.py         device list and sign-out
        items.py            create, update, delete
        sync.py             changes since a revision
        sharing.py          lookup, grants, revoke with rotation
    tests/
  app/                      Flutter project
    lib/
      main.dart
      core/
        crypto/             key derivation, encrypt and decrypt, sharing
        api/                HTTP client
        store/              local ciphertext store
        sync/               sync engine and three-way merge
        health/             strength and breach checks
      models/               vault item and account state
      services/             vault session: lock state and app logic
      ui/
        onboarding/         welcome, register, login, unlock, recovery
        vault/              list, detail, edit, conflict
        sharing/            share and fingerprints
        generator/
        health/
        settings/           devices, password change
        widgets/
    test/                   host tests (no native code)
    integration_test/       device tests (real libsodium, live server)
    tool/test.sh            runs both
```
