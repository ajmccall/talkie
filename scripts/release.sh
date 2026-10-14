#!/bin/bash
# Cuts a Talkie release: build, sign (notarise when a Developer ID exists),
# zip, tag, publish on GitHub Releases, and bump the Homebrew cask.
#
#   scripts/release.sh                full release
#   scripts/release.sh --dry-run      build, sign, zip and print the sha; no tag, release or tap
#   scripts/release.sh --skip-tap     publish the release but leave the cask alone
#   scripts/release.sh --skip-notarize  Developer ID signing without notarisation
#   scripts/release.sh --skip-tests
#
# Environment (all optional):
#   TALKIE_REPO            GitHub repo (default ajmccall/talkie)
#   TALKIE_TAP_REPO        tap repo (default ajmccall/homebrew-tap)
#   TALKIE_TAP_DIR         local tap checkout (default ../homebrew-tap, cloned if missing)
#   TALKIE_SIGN_IDENTITY   certificate hash or name; a "Developer ID Application"
#                          one turns on hardened runtime and notarisation
#   TALKIE_NOTARY_PROFILE  notarytool keychain profile (xcrun notarytool store-credentials)
#   APP_STORE_CONNECT_KEY_ID / APP_STORE_CONNECT_ISSUER_ID / APP_STORE_CONNECT_API_KEY_PATH
#                          alternative to the keychain profile
set -euo pipefail
cd "$(dirname "$0")/.."

DRY_RUN=0; SKIP_TAP=0; SKIP_NOTARIZE=0; SKIP_TESTS=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --skip-tap) SKIP_TAP=1 ;;
    --skip-notarize) SKIP_NOTARIZE=1 ;;
    --skip-tests) SKIP_TESTS=1 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

step() { printf '\n==> %s\n' "$1"; }
fail() { printf 'error: %s\n' "$1" >&2; exit 1; }
warn() { printf '\nWARNING: %s\n' "$1" >&2; }

REPO="${TALKIE_REPO:-ajmccall/talkie}"
TAP_REPO="${TALKIE_TAP_REPO:-ajmccall/homebrew-tap}"
TAP_DIR="${TALKIE_TAP_DIR:-../homebrew-tap}"
# shellcheck source=../version.env
source version.env
V="$MARKETING_VERSION"
TAG="v$V"
ZIP="build/Talkie-$V.zip"
NOTES="build/release-notes.md"

step "Preconditions for Talkie $V (build $BUILD_NUMBER)"
command -v gh >/dev/null || fail "gh (GitHub CLI) is required."
gh auth status >/dev/null 2>&1 || fail "gh is not signed in. Run: gh auth login"
[ -z "$(git status --porcelain)" ] || fail "Working tree is dirty. Commit or stash first."
if [ "$DRY_RUN" = 0 ]; then
  ! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || fail "Tag $TAG already exists locally."
  ! git ls-remote --exit-code --tags origin "$TAG" >/dev/null 2>&1 || fail "Tag $TAG already exists on origin."
fi
branch="$(git rev-parse --abbrev-ref HEAD)"
[ "$branch" = main ] || warn "Releasing from branch '$branch', not main."

# CHANGELOG: Unreleased must be empty and the first dated section must be $V.
mkdir -p build
awk -v v="$V" '
  /^## / { if (section == "unreleased" && body != "") { print "UNRELEASED_NOT_EMPTY" > "/dev/stderr"; exit 1 }
           if (section == "target") exit
           if ($2 == "Unreleased") section = "unreleased"
           else if ($2 == v) section = "target"
           else if (section == "unreleased") { print "FIRST_SECTION_IS " $2 > "/dev/stderr"; exit 1 }
           next }
  section == "unreleased" && NF > 0 { body = body $0 }
  section == "target" { print }
' CHANGELOG.md > "$NOTES" 2>build/changelog-check.txt || true
if [ -s build/changelog-check.txt ]; then
  fail "CHANGELOG.md: $(cat build/changelog-check.txt). Move the notes under '## $V - $(date +%F)' and leave Unreleased empty."
fi
[ -s "$NOTES" ] || fail "CHANGELOG.md has no '## $V' section."
echo "Release notes:"; sed 's/^/  /' "$NOTES"

if [ "$SKIP_TESTS" = 0 ]; then
  step "Running unit tests"
  swift test 2>&1 | tail -1
fi

step "Choosing a signing identity"
identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
NOTARIZE=0
if [ -n "${TALKIE_SIGN_IDENTITY:-}" ]; then
  line="$(printf '%s\n' "$identities" | grep -F "$TALKIE_SIGN_IDENTITY" | head -1 || true)"
else
  line="$(printf '%s\n' "$identities" | grep 'Developer ID Application' | head -1 || true)"
fi
if printf '%s' "$line" | grep -q 'Developer ID Application'; then
  export TALKIE_SIGN_IDENTITY="$(printf '%s\n' "$line" | awk '{print $2}')"
  export TALKIE_HARDENED=1
  NOTARIZE=1
  echo "Developer ID found: $(printf '%s\n' "$line" | sed 's/.*"\(.*\)"/\1/'). Hardened runtime + notarisation."
else
  if printf '%s\n' "$identities" | grep -q 'Apple Development'; then
    echo "No Developer ID certificate. Signing with an Apple Development identity."
  else
    echo "No certificate at all. Signing ad-hoc."
    warn "Ad-hoc signatures change every build, so macOS re-asks for Microphone and Accessibility after each update."
  fi
  warn "This build is NOT notarised. Gatekeeper will call it damaged on other Macs unless they install with
         brew install --cask --no-quarantine $TAP_REPO/talkie   (or: xattr -dr com.apple.quarantine /Applications/Talkie.app)
         Join the Apple Developer Program and add a 'Developer ID Application' certificate to fix this."
fi

step "Building and signing"
scripts/build-app.sh release
built="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' build/Talkie.app/Contents/Info.plist)"
[ "$built" = "$V" ] || fail "Built app reports version $built, expected $V."
codesign --verify --deep --strict --verbose=2 build/Talkie.app
spctl -a -t exec -vv build/Talkie.app 2>&1 || echo "(spctl rejection is expected without Developer ID + notarisation)"

if [ "$NOTARIZE" = 1 ] && [ "$SKIP_NOTARIZE" = 0 ]; then
  step "Notarising"
  notary_zip="build/Talkie-$V-notary.zip"
  rm -f "$notary_zip"
  /usr/bin/ditto -c -k --keepParent build/Talkie.app "$notary_zip"
  if [ -n "${TALKIE_NOTARY_PROFILE:-}" ]; then
    xcrun notarytool submit "$notary_zip" --keychain-profile "$TALKIE_NOTARY_PROFILE" --wait
  elif [ -n "${APP_STORE_CONNECT_KEY_ID:-}" ]; then
    xcrun notarytool submit "$notary_zip" --key "$APP_STORE_CONNECT_API_KEY_PATH" \
      --key-id "$APP_STORE_CONNECT_KEY_ID" --issuer "$APP_STORE_CONNECT_ISSUER_ID" --wait
  else
    fail "Set TALKIE_NOTARY_PROFILE or APP_STORE_CONNECT_* for notarisation, or pass --skip-notarize."
  fi
  xcrun stapler staple build/Talkie.app
  xcrun stapler validate build/Talkie.app
  rm -f "$notary_zip"
fi

step "Packaging"
rm -f "$ZIP"
/usr/bin/ditto -c -k --keepParent build/Talkie.app "$ZIP"
SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
echo "$SHA" > "$ZIP.sha256"
echo "$ZIP"; echo "sha256 $SHA"

if [ "$DRY_RUN" = 1 ]; then
  step "Dry run: stopping before tag, release and tap"
  echo "Would: git tag -a $TAG && git push origin HEAD --tags"
  echo "Would: gh release create $TAG $ZIP --repo $REPO --title 'Talkie $V' --notes-file $NOTES"
  [ "$SKIP_TAP" = 1 ] || echo "Would: update $TAP_DIR/Casks/talkie.rb to version $V, sha256 $SHA, and push"
  exit 0
fi

step "Tagging and publishing $TAG"
git tag -a "$TAG" -m "Talkie $V"
git push origin HEAD --tags
gh release create "$TAG" "$ZIP" "$ZIP.sha256" --repo "$REPO" --title "Talkie $V" --notes-file "$NOTES"

if [ "$SKIP_TAP" = 0 ]; then
  step "Updating the Homebrew cask in $TAP_REPO"
  if [ ! -d "$TAP_DIR/.git" ]; then
    gh repo clone "$TAP_REPO" "$TAP_DIR"
  fi
  git -C "$TAP_DIR" pull --ff-only
  cask="$TAP_DIR/Casks/talkie.rb"
  [ -f "$cask" ] || fail "$cask not found. Create it first (see docs/REVIEW.md, Distribution)."
  sed -i '' -e "s/^  version \".*\"/  version \"$V\"/" -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$cask"
  git -C "$TAP_DIR" add Casks/talkie.rb
  git -C "$TAP_DIR" commit -m "talkie $V"
  git -C "$TAP_DIR" push
fi

cat <<EOT

Released Talkie $V.
  Install:  brew install --cask $TAP_REPO/talkie
  Upgrade:  brew update && brew upgrade --cask talkie
  Release:  https://github.com/$REPO/releases/tag/$TAG
EOT
