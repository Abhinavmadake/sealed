# Sealed: demo script

About 10 minutes. Every step below was run on 2026-11-13 against the Android emulator, Chrome
and the Python client in `tools/`.

## Before the demo

```sh
# terminal 1: server and database
cd server && ./run_dev.sh

# terminal 2: Android emulator, then the app
cd app && flutter run

# terminal 3: second device in Chrome
cd app && flutter run -d chrome

# terminal 4: independent Python client
cd tools && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
```

Demo accounts are in `.demo-accounts` (not committed). Below, `A` is the first account and `B`
is the second. On the emulator, enrol a fingerprint first if fingerprint unlock is part of the demo:
`adb emu finger touch 1` then `adb emu finger remove`.

## 1. The server cannot read the vault

1. Phone: sign in as A, open an item, show the password.
2. Database:
   ```sh
   psql sealed -c "select email, left(auth_hash,34), length(wrapped_account_key) from users"
   psql sealed -c "select id, revision, length(blob), left(encode(blob,'base64'),40) from items where deleted_at is null"
   psql sealed -Atc "select count(*) from items where encode(blob,'escape') ilike '%github%'"
   ```
   Expect: an Argon2 hash instead of a password, blobs of 297 bytes (41 bytes of overhead plus one
   256-byte padding block) whatever the content, and `0` for the search.
3. Python client: `second_device.py A PASSWORD raw` prints what the server returns, then `list`
   decrypts the same data locally. It shares no code with the app.

## 2. Two devices and offline editing

1. Chrome: sign in as A. The same items appear.
2. Phone: turn on aeroplane mode, edit the username of an item, save. The sync icon shows a badge.
3. Chrome (or `second_device.py A PASSWORD set GitHub username other-name`): change the same
   username, and also change the website.
4. Phone: turn aeroplane mode off and tap the sync icon.
   Expect: a red banner, "1 item(s) were changed on two devices and need your choice".
5. Tap Review, then the conflict card. Only Username is listed: the website was merged
   automatically. Pick a side, tap Keep these choices.
6. Chrome: sync. Both devices show the same item.

## 3. Sharing and revoking

1. Phone, as A: open an item, tap Share, find B. Compare the fingerprint with the one on B's
   Settings screen. Share with Can edit.
2. `second_device.py B PASSWORD list` shows the item with permission `write`.
   `second_device.py B PASSWORD set GitHub notes "from B"`, then sync on the phone to see the note.
3. Phone: Share, Stop sharing with B.
4. `second_device.py B PASSWORD list` is empty. A still reads the item.
5. Database: `select key_kind, permission, revoked_at from grants order by revision desc limit 3`
   shows the revoked grant and a new revision for the owner's re-wrapped key.

## 4. Devices and sessions

1. Phone: Settings, Signed-in devices. The phone, the browser and "Laptop (script)" are listed.
2. Tap Sign out next to the browser. On its next sync Chrome shows "This device was signed out,
   so changes are not syncing" with a Sign in button. The vault stays readable offline.

## 5. Master password and recovery

1. Phone: Settings, Change master password. It takes a few seconds whatever the vault size:
   two key derivations, then only the account key is re-wrapped. Other devices are signed out.
2. Lock, then unlock with the new password.
3. Sign out of the device. On the welcome screen: Sign in, Forgot your master password?
   Enter the recovery key from sign-up and a new password. The vault comes back.

## 6. Vault health and generator

1. Add two logins with the password `password123`.
2. Menu, Vault health: both are listed as weak and reused, and the score drops.
3. Check for breaches: both show as seen in breaches. Only five characters of each SHA-1 hash
   leave the device.
4. Menu, Generator: random and passphrase modes.

## 7. Fingerprint unlock

1. Phone: Settings, Unlock with fingerprint, confirm with the fingerprint.
2. Lock now. The prompt appears; touch the sensor to unlock.
3. Lock again and choose Use master password to show the fallback.

## What the demo does not hide

The limits in section 7 of `PLAN.md`: metadata is visible to the server, a revoked user keeps
what they already saw, and losing both the password and the recovery key loses the vault.
