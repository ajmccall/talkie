#!/bin/bash
# First-time setup on a new Mac: verifies the toolchain, builds Talkie,
# installs it to /Applications and launches it.
#
#   scripts/setup.sh            full setup
#   scripts/setup.sh --no-fn    leave the Fn key system setting alone
#   scripts/setup.sh --no-install  build only, don't copy to /Applications
set -euo pipefail
cd "$(dirname "$0")/.."

SET_FN=1
INSTALL=1
for arg in "$@"; do
  case "$arg" in
    --no-fn) SET_FN=0 ;;
    --no-install) INSTALL=0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

step() { printf '\n==> %s\n' "$1"; }
fail() { printf 'error: %s\n' "$1" >&2; exit 1; }

step "Checking hardware and OS"
[ "$(uname -m)" = "arm64" ] || fail "Talkie needs Apple silicon (MLX has no Intel build)."
os_major="$(sw_vers -productVersion | cut -d. -f1)"
[ "$os_major" -ge 15 ] || fail "macOS 15 or later required (found $(sw_vers -productVersion))."
echo "macOS $(sw_vers -productVersion) on $(uname -m)"

step "Checking Xcode"
if ! xcode-select -p >/dev/null 2>&1 || ! xcodebuild -version >/dev/null 2>&1; then
  fail "Xcode is not installed or not selected. Install Xcode 26 or later from the App Store, then run: sudo xcode-select -s /Applications/Xcode.app"
fi
xcodebuild -version | head -1
swift_major="$(swift --version 2>&1 | grep -oE 'Swift version [0-9]+' | grep -oE '[0-9]+$' || echo 0)"
[ "$swift_major" -ge 6 ] || fail "Swift 6 or later required."

step "Checking Metal Toolchain (needed to compile MLX shaders)"
if xcrun metal --version >/dev/null 2>&1; then
  xcrun metal --version | head -1
else
  echo "Not installed; downloading via xcodebuild (a few hundred MB)…"
  xcodebuild -downloadComponent MetalToolchain
  xcrun metal --version >/dev/null 2>&1 || fail "Metal Toolchain still unavailable after download."
fi

if [ "$SET_FN" = 1 ]; then
  step "Setting the Fn key to 'Do Nothing' (System Settings → Keyboard)"
  current="$(defaults read com.apple.HIToolbox AppleFnUsageType 2>/dev/null || echo unset)"
  if [ "$current" != "0" ]; then
    defaults write com.apple.HIToolbox AppleFnUsageType -int 0
    echo "Changed from '$current' to 0. Otherwise macOS would also trigger Dictation or the emoji picker on Fn."
  else
    echo "Already set."
  fi
fi

step "Building Talkie (first build compiles MLX; expect several minutes)"
scripts/build-app.sh

if [ "$INSTALL" = 1 ]; then
  step "Installing to /Applications"
  pkill -x Talkie 2>/dev/null || true
  rm -rf /Applications/Talkie.app
  cp -R build/Talkie.app /Applications/Talkie.app
  open /Applications/Talkie.app
  echo "Launched."
fi

cat <<'EOF'

==> Next steps (one-time, in the dialogs macOS shows)
  1. Allow Microphone access.
  2. Allow Accessibility access. This lets Talkie see the Fn key system-wide and send ⌘V.
     Talkie picks the grant up automatically; no relaunch needed.
  3. Wait for the menu-bar mic icon to stop showing the download arrow.
     First launch downloads ~3 GB of models (Parakeet, Qwen3) and caches them.
  4. Hold Fn, speak, release.

If the signature is ad-hoc (no "Apple Development" certificate on this Mac), macOS forgets
the permission grants whenever you rebuild. Create a development certificate in Xcode
(Settings → Accounts → Manage Certificates) to avoid that.
EOF
