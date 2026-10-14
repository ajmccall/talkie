#!/bin/bash
# Builds Talkie with SwiftPM and assembles a signed Talkie.app in ./build.
#
# Version comes from version.env. Signing: $TALKIE_SIGN_IDENTITY if set;
# otherwise the "Apple Development" identity for $TALKIE_SIGN_ACCOUNT if set;
# otherwise any "Apple Development" identity; otherwise ad-hoc ("-").
# A real identity keeps the code signature stable across rebuilds, which
# stops macOS from forgetting the Accessibility and Microphone grants.
# TALKIE_HARDENED=1 (set by release.sh with a Developer ID) adds the hardened
# runtime and a secure timestamp, which notarisation requires.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
# shellcheck source=../version.env
source version.env
swift build -c "$CONFIG"

BIN=".build/$CONFIG"
APP="build/Talkie.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN/Talkie" "$APP/Contents/MacOS/Talkie"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MARKETING_VERSION" \
                        -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
[ -f Resources/Talkie.icns ] && cp Resources/Talkie.icns "$APP/Contents/Resources/Talkie.icns"

# SwiftPM resource bundles (MLX Metal library, FluidAudio assets) are looked up
# relative to the executable's bundle, so they must live in Contents/Resources.
for bundle in "$BIN"/*.bundle; do
  [ -d "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done

IDENTITY="${TALKIE_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  identities="$(security find-identity -v -p codesigning 2>/dev/null | grep 'Apple Development' || true)"
  if [ -n "${TALKIE_SIGN_ACCOUNT:-}" ]; then
    IDENTITY="$(printf '%s\n' "$identities" | grep -F "$TALKIE_SIGN_ACCOUNT" | head -1 | awk '{print $2}' || true)"
  fi
  [ -n "$IDENTITY" ] || IDENTITY="$(printf '%s\n' "$identities" | head -1 | awk '{print $2}' || true)"
fi
IDENTITY="${IDENTITY:--}"

SIGN_OPTS=()
if [ "${TALKIE_HARDENED:-0}" = 1 ]; then
  SIGN_OPTS+=(--options runtime --timestamp)
  [ -f Resources/Talkie.entitlements ] && SIGN_OPTS+=(--entitlements Resources/Talkie.entitlements)
fi
# Strip metadata that would break the seal (AppleDouble files after a copy).
xattr -cr "$APP"
codesign --force --deep "${SIGN_OPTS[@]+"${SIGN_OPTS[@]}"}" --sign "$IDENTITY" --identifier com.alasdairmccall.talkie "$APP"
echo "Built $APP $MARKETING_VERSION ($BUILD_NUMBER), signed with ${IDENTITY}"
