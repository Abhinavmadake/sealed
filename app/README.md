# Sealed app

Flutter client for Sealed. Setup and run instructions are in the [top-level README](../README.md).

## Layout

```
lib/
  main.dart           app start and root routing by vault status
  core/
    crypto/           key derivation, encrypt and decrypt, sharing (libsodium)
    biometric/        fingerprint unlock (flutter_secure_storage, local_auth)
    api/              HTTP client and response types
    store/            local ciphertext store (sembast)
    sync/             sync engine, three-way merge, vault repository
    health/           strength, breach check, generator
  models/             vault item
  services/           vault session, auth flows, sharing
  ui/                 screens
test/                 host tests (no native code)
integration_test/     device tests (real libsodium, live server)
tool/test.sh          runs both
```

## Notes

- The Dart package is `sealed_app` because `sealed` is a reserved word.
- `sodium` is pinned to 4.0.4. Host tests run with `NIX_SKIP_SODIUM_BUILD_HOOKS=1`, so
  anything that touches real crypto lives in `integration_test/`.
- `flutter test integration_test` uninstalls the app afterwards and overwrites the debug APK,
  so rebuild before reinstalling.
- Fingerprint unlock uses `flutter_secure_storage` 11 in per-operation biometric mode. The plugin
  never reports the prompt's negative button, so the unlock screen does not wait on that call.
  On the emulator, `adb emu finger touch 1` holds the finger down until `adb emu finger remove`.
