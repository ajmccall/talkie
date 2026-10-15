# Developing Talkie

Building from source needs more than running the app does:

- Full Xcode 26 or later, with the Metal Toolchain component. The Command
  Line Tools alone are not enough: MLX needs the Metal compiler, which only
  ships with Xcode. `scripts/setup.sh` installs the component if missing and
  offers to install Xcode itself with
  [xcodes](https://github.com/XcodesOrg/xcodes).
- About 4 GB of disk for models and build output.

```sh
git clone https://github.com/ajmccall/talkie.git
cd talkie
make setup
```

`make setup` checks the toolchain, sets the Fn key to "Do Nothing" (pass
`--no-fn` to `scripts/setup.sh` to skip that), builds, installs to
`/Applications/Talkie.app` and launches.

## Everyday commands

The full list is at the top of the `Makefile`. The ones you will use:

| Command | What it does |
|---|---|
| `make install` | Rebuild, replace `/Applications/Talkie.app`, relaunch |
| `make run` | Rebuild and launch from `./build` without installing |
| `make test` | Unit tests for the pure helpers |
| `make selftest AUDIO=file.aiff` | Run transcribe → clean on an audio file and print both outputs. Without `AUDIO`, synthesises a sample with `say`. Add `VOCAB=list.txt` (one term per line, `Alfie: Alfy, Alfi`) to try the vocabulary pass |
| `scripts/skill-timing.sh` | Time a Claude Code skill run cold versus pre-warmed, per model. Makes a few small API calls on your login |

Where things live, and why they are the way they are, is in
[AGENTS.md](../AGENTS.md). It is written for coding agents but is the file
map for people too. [REVIEW.md](REVIEW.md) has the deliberate choices and
known limitations.

## Code signing and permissions

`scripts/build-app.sh` signs with an "Apple Development" certificate if one
is in the keychain (`TALKIE_SIGN_ACCOUNT` picks between several,
`TALKIE_SIGN_IDENTITY` names one outright), otherwise ad-hoc. macOS ties the
Microphone and Accessibility grants to the signature, and an ad-hoc signature
changes on every build, so without a certificate you are re-prompted after
each rebuild. Create one in Xcode → Settings → Accounts → Manage Certificates.

## Logs

```sh
/usr/bin/log stream --info --predicate 'subsystem == "talkie"'
```

`/usr/bin/log` rather than `log`, because zsh has a builtin of the same name.
Transcripts are logged as private and are redacted unless you enable private
data in the logging profile.

## Releasing

Versions live in `version.env`; notes live in `CHANGELOG.md`. To cut a
release:

1. Move the notes from `Unreleased` under a `## x.y.z - date` heading and
   bump `version.env`. Commit.
2. `make release-dry` builds, signs and zips, and prints the sha256.
3. `make release` tags `vx.y.z`, creates the GitHub release with the zip and
   the changelog section as notes, and updates `Casks/talkie.rb` in
   `ajmccall/homebrew-tap` (cloned to `../homebrew-tap` if missing).

The script signs with a "Developer ID Application" certificate and notarises
when one is present (set `TALKIE_NOTARY_PROFILE` to a `notarytool` keychain
profile), otherwise it signs with Apple Development or ad-hoc and warns that
users need the `xattr` step.

CI (`.github/workflows/build.yml`) builds, tests and uploads an ad-hoc zip as
an artifact on every push. It has not been exercised on a real runner yet.
