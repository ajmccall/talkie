#!/bin/bash
# Builds Talkie with SwiftPM and assembles a signed Talkie.app in ./build.
#
# Signing: uses $TALKIE_SIGN_IDENTITY if set; otherwise the "Apple Development"
# identity for $TALKIE_SIGN_ACCOUNT (default alasdair.mccall@gmail.com); otherwise
# any "Apple Development" identity; otherwise ad-hoc ("-").
# A real identity keeps the code signature stable across rebuilds, which
# stops macOS from forgetting the Accessibility and Microphone grants.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
swift build -c "$CONFIG"

BIN=".build/$CONFIG"
APP="build/Talkie.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN/Talkie" "$APP/Contents/MacOS/Talkie"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# SwiftPM resource bundles (MLX Metal library, FluidAudio assets) are looked up
# relative to the executable's bundle, so they must live in Contents/Resources.
for bundle in "$BIN"/*.bundle; do
  [ -d "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done

IDENTITY="${TALKIE_SIGN_IDENTITY:-}"
PREFERRED_ACCOUNT="${TALKIE_SIGN_ACCOUNT:-alasdair.mccall@gmail.com}"
if [ -z "$IDENTITY" ]; then
  identities="$(security find-identity -v -p codesigning 2>/dev/null | grep 'Apple Development' || true)"
  # Prefer the personal-account certificate, then any Apple Development one.
  IDENTITY="$(printf '%s\n' "$identities" | grep -F "$PREFERRED_ACCOUNT" | head -1 | awk '{print $2}' || true)"
  [ -n "$IDENTITY" ] || IDENTITY="$(printf '%s\n' "$identities" | head -1 | awk '{print $2}' || true)"
fi
IDENTITY="${IDENTITY:--}"

codesign --force --deep --sign "$IDENTITY" --identifier com.alasdairmccall.talkie "$APP"
echo "Built $APP (signed with ${IDENTITY})"
