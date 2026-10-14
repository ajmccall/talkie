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
# Full Xcode is required, not just the Command Line Tools: MLX compiles Metal
# shaders, and the Metal compiler only ships with Xcode's Metal Toolchain.
xcode_app="$(ls -d /Applications/Xcode*.app 2>/dev/null | sort -V | tail -1 || true)"
[ -n "$xcode_app" ] || xcode_app="$(mdfind 'kMDItemCFBundleIdentifier == "com.apple.dt.Xcode"' 2>/dev/null | head -1 || true)"
if [ -z "$xcode_app" ]; then
  echo "Xcode is not installed."
  if [ -t 0 ] && command -v brew >/dev/null 2>&1; then
    # Offer to install via xcodes (https://github.com/XcodesOrg/xcodes). It needs
    # an Apple ID (prompted for interactively) and downloads a ~3 GB .xip.
    printf 'Install the latest Xcode now with xcodes? Needs your Apple ID and ~3 GB download. [y/N] '
    read -r answer
    if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
      if ! command -v xcodes >/dev/null 2>&1; then
        step "Installing xcodes and aria2 via Homebrew"
        brew install xcodesorg/made/xcodes aria2
      fi
      step "Installing the latest Xcode (this takes a while)"
      xcodes install --latest --select --experimental-unxip --empty-trash
      xcode_app="$(xcodes installed 2>/dev/null | grep -i selected | awk -F'\t' '{print $NF}' || true)"
      [ -n "$xcode_app" ] || xcode_app="$(ls -d /Applications/Xcode*.app 2>/dev/null | sort -V | tail -1 || true)"
      [ -n "$xcode_app" ] || fail "xcodes finished but no Xcode was found in /Applications."
    fi
  fi
  [ -n "$xcode_app" ] || fail "Install Xcode 26 or later from the App Store (or https://developer.apple.com/xcode/), open it once to finish installing components, then rerun this script.
Or install it from the terminal:  brew install xcodesorg/made/xcodes aria2 && xcodes install --latest --select"
fi

dev_dir="$(xcode-select -p 2>/dev/null || true)"
case "$dev_dir" in
  */Xcode*.app/Contents/Developer) ;;
  *)
    fail "Xcode is installed at $xcode_app but the active developer directory is '${dev_dir:-unset}' (probably the Command Line Tools). Select Xcode with:
    sudo xcode-select -s \"$xcode_app\"" ;;
esac

if ! xcodebuild -version >/dev/null 2>&1; then
  if xcodebuild -version 2>&1 | grep -qi 'license'; then
    fail "Xcode licence not accepted. Run: sudo xcodebuild -license accept"
  fi
  fail "xcodebuild failed to run. Open $xcode_app once so it can install its components, then rerun. Output was:
$(xcodebuild -version 2>&1 | head -3)"
fi
xcode_major="$(xcodebuild -version | grep -oE 'Xcode [0-9]+' | grep -oE '[0-9]+$' || echo 0)"
[ "$xcode_major" -ge 26 ] || fail "Xcode 26 or later required (found $(xcodebuild -version | head -1)). Update from the App Store."
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

==> Next steps
  Talkie opens a Welcome window with a checklist on first launch:
  1. Allow Microphone access.
  2. Allow Accessibility access. This lets Talkie see the Fn key system-wide and send ⌘V.
     Talkie picks the grant up automatically; no relaunch needed.
  3. Wait for the models to download (~2.6 GB, once). The menu-bar icon shows an arrow meanwhile.
  4. Hold Fn, speak, release.
  (None of this script is needed to run a prebuilt Talkie: see Install in the README.)

If the signature is ad-hoc (no "Apple Development" certificate on this Mac), macOS forgets
the permission grants whenever you rebuild. Create a development certificate in Xcode
(Settings → Accounts → Manage Certificates) to avoid that.
EOF
