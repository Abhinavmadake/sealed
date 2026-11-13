#!/bin/sh
# Host tests never touch libsodium, so skip building it for macOS.
# Crypto and sync tests need the real library and the server, so they run on a device.
set -e
cd "$(dirname "$0")/.."
NIX_SKIP_SODIUM_BUILD_HOOKS=1 flutter test test
DEVICE="${1:-$(flutter devices --machine 2>/dev/null | python3 -c 'import json,sys; d=[x["id"] for x in json.load(sys.stdin) if x["targetPlatform"].startswith("android")]; print(d[0] if d else "")')}"
[ -n "$DEVICE" ] || { echo "start an Android emulator first"; exit 1; }
flutter test integration_test -d "$DEVICE"
