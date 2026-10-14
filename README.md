# Talkie

**Hold Fn, talk, let go.** Talkie transcribes what you said on-device, tidies
it up with a small local language model, and pastes it wherever your cursor
is. No accounts, no cloud, no subscription. Optionally, hold Shift as well to
send that one dictation through a skill using a Codex or Claude Code login you
already have (see [Skills](#skills-optional)).

## Install

On an Apple silicon Mac running macOS 15 or later:

```sh
brew install --cask --no-quarantine ajmccall/tap/talkie
```

Or download `Talkie-<version>.zip` from
[GitHub Releases](https://github.com/ajmccall/talkie/releases), unzip, drag
`Talkie.app` to Applications, then run
`xattr -dr com.apple.quarantine /Applications/Talkie.app` once.

Why the extra step: Talkie is not yet notarised by Apple, so Gatekeeper calls
a downloaded copy "damaged" until the quarantine flag is removed. The
`--no-quarantine` flag and the `xattr` command do exactly that and nothing
else. (System Settings → Privacy & Security → "Open Anyway" also works.) This
goes away once the app is notarised.

Updates: `brew upgrade --cask talkie`. Uninstall: `brew uninstall --cask
talkie`; the speech models stay cached, see [How it works](#how-it-works).

## Requirements

- Apple silicon Mac, macOS 15 or later
- About 2.6 GB of disk for the speech models, downloaded once on first launch
- No Xcode, no Python, no accounts. (Building from source is different, see
  [Development](#development).)

## First run

Talkie lives in the menu bar (a microphone icon) and opens a Welcome window
the first time, with a checklist that updates as you go:

1. **Microphone**: allow when macOS asks.
2. **Accessibility**: allow. This one permission covers both noticing the Fn
   key system-wide and sending ⌘V. Talkie notices the grant within a couple
   of seconds; no relaunch needed. Until then it copies text but cannot paste.
3. **Fn key set to "Do Nothing"**: by default macOS binds Fn to Dictation or
   the emoji picker, so every press would also trigger that. The Welcome
   window's "Set it" button changes the setting (the same as System Settings →
   Keyboard → "Press 🌐 key to"). If Fn still opens Dictation afterwards, log
   out and back in.
4. **Speech models**: Parakeet (0.5 GB) and Qwen3 (2.1 GB) download once; the
   menu-bar icon shows a download arrow and the window shows progress.

When the status reads "Ready. Hold Fn to dictate", you are done. The window
can be reopened any time from the menu: **Welcome / How Talkie works…**.

## Quick start

Put the cursor where you want text, hold **Fn**, speak, let go. A small pill
at the bottom of the screen shows "Listening…", then "Transcribing…", then the
text is pasted. Menu-bar items: the Qwen3 cleanup toggle (raw transcription is
pasted when off), **Sounds**, the optional Skills section, Launch at Login,
and shortcuts to the relevant privacy settings.

## Skills *(optional)*

Fn alone is the whole product, needs no account, and never leaves the
machine. Optionally, you can connect a **Codex** or **Claude Code** login
(the CLI you already use; Talkie never sees the tokens) and choose a skill.
Holding **Shift** at any point while Fn is held then sends that one dictation
through the skill before it is pasted. The immediate use is a Slack reword
skill, but any SKILL.md whose job is to rewrite text will do.

1. **Connect Codex…** in the menu. Talkie looks for the Codex CLI in the usual
   places (the ChatGPT and Codex apps, `~/.local/bin`, Homebrew, and the newest
   nvm install) and asks it whether it is signed in with ChatGPT. If not, run
   `codex login` in Terminal and use **Check Connection**. If the CLI is
   somewhere unusual, **Choose Codex Executable…**. Talkie never sees your
   tokens; it only runs the CLI, which holds the login.
2. **Skills ▸ Add Skill…** and pick one or more `SKILL.md` files, for example
   `~/.agents/skills/slack-reword/SKILL.md`. Skills are re-read on every
   dictation, so edits apply immediately. **Skills ▸ Remove ▸** takes one out
   again; ticking an entry makes it the pre-selected skill.
3. Hold Fn and Shift, speak, release. A picker appears in place of the HUD
   the moment you let go, listing your skills with the last-used one
   highlighted, and shows "Transcribing…" then "Ready" while Talkie works.
   - **Enter** applies the highlighted skill (you can press it before "Ready";
     it applies as soon as the text is there).
   - **↑ ↓**, the mouse, or the number keys **1–9** change the highlight.
   - **Escape**, or clicking into another window, pastes the transcription
     as-is.
   The picker takes keyboard focus without activating Talkie, so the app you
   were in stays frontmost and receives the paste. Fn does nothing while the
   picker is open.

How a skill is run: Talkie wraps the skill and the transcript in a prompt that
treats the transcript as data, forbids questions (the model assumes instead),
forbids tools, and asks for structured JSON. Codex runs ephemeral and
read-only with every tool disabled, exactly as the Reword app does. A failure,
timeout (90 s) or bad response pastes the cleaned transcript instead and the
HUD says why, e.g. "Pasted (reword failed: signed out)". Fn+Shift without a
connected account or chosen skill pastes the cleaned transcript and says so.

**Claude Code** works the same way: **Connect Claude Code…** finds the
`claude` CLI (`~/.local/bin`, Homebrew, or nvm) and checks `claude auth status`.
Skills run with `claude -p`, no tools, no hooks, no CLAUDE.md or memory, and a
JSON schema for the reply; the default model is `sonnet`. If your login lives
in a profile folder rather than `~/.claude` (you set `CLAUDE_CONFIG_DIR` in the
shell), point Talkie at it with **Choose Claude Config Folder…**. One account
is connected at a time; Disconnect and connect the other to switch.

## Sounds

**Sounds ▸** in the menu picks a set of cues for start, stop, paste and
failure. Soft Chime (the default), Marimba, Muted Glass and Minimal are
synthesised by Talkie itself and kept quiet and rounded; macOS Sounds uses the
bundled Tink, Pop, Glass and Basso; Off is silent. Choosing a theme plays its
"pasted" sound, **Play Start, Stop, Pasted** runs through a whole dictation,
and Quiet halves the volume. The notes behind each theme live in
`Sources/Talkie/Sounds.swift` if you want to tune them.

## Behaviour details

- Presses shorter than 0.25 s, or recordings under 0.5 s, are ignored.
- Recording stops by itself after 5 minutes. For the last 30 s the HUD turns
  amber and counts down ("Listening… 4:35 · stops at 5:00") with a soft sound
  when the countdown starts; if the cap cuts the recording, the HUD says
  "Max length reached, transcribing…" and what was captured is still pasted.
- If Qwen3 takes longer than 30 s, or returns something that is not a light
  edit (empty, more than double the length, or under a third of it), the raw
  transcript is pasted instead and the HUD says why, e.g.
  "Pasted (raw: cleanup timed out)".
- Fn pressed while models load or the previous dictation is still processing
  shows a message and does nothing.
- A skill that fails or times out leaves the cleaned transcript to be pasted,
  with the reason in the HUD, same as the Qwen3 fallback above.
- While the skill picker is open, Fn shows "Still working on the last one…".
- The clipboard is deliberately left holding the dictated text.
- Apps with Secure Keyboard Entry on (password fields, Terminal with the
  option enabled) swallow the synthetic ⌘V. The text is still on the clipboard.

## How it works

| Stage | What runs | Where it comes from |
|---|---|---|
| Hotkey | `NSEvent` flags-changed monitor on the Fn key (key code 63) | built in |
| Capture | `AVAudioEngine` input tap, mono float samples | built in |
| Transcribe | NVIDIA Parakeet TDT 0.6B v3, Core ML, via [FluidAudio](https://github.com/FluidInference/FluidAudio) (Apache 2.0) | `FluidInference/parakeet-tdt-0.6b-v3-coreml` on Hugging Face |
| Clean up | Qwen3 4B, 4-bit, via [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) (MIT) | `mlx-community/Qwen3-4B-4bit` on Hugging Face |
| Paste | Text goes on the clipboard, then a synthetic ⌘V is sent | built in |

Both models download on first launch and are cached under
`~/Library/Application Support/FluidAudio/Models` and
`~/.cache/huggingface/hub`. Those folders are shared with other tools, so
uninstalling Talkie leaves them alone; delete them by hand (or `make
models-clean` from a checkout) to reclaim the space.

Privacy: audio and text never leave the Mac. The one exception is a skill
run (Fn+Shift), which sends the cleaned text to the Codex or Claude Code CLI
you connected, under your own login. On an M-series Mac, 8 seconds of speech
transcribes in about 0.1 s and cleans up in about 0.7 s.

## Development

Building from source needs more than running the app does:

- Full Xcode 26 or later (the Command Line Tools alone are not enough: MLX
  needs the Metal compiler, which only ships with Xcode), with the Metal
  Toolchain component. `scripts/setup.sh` installs that component if missing
  and offers to install Xcode itself with
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

| Command | What it does |
|---|---|
| `make install` | Rebuild, replace `/Applications/Talkie.app`, relaunch |
| `make run` | Rebuild and launch from `./build` without installing |
| `make test` | Unit tests for the pure helpers |
| `make selftest AUDIO=file.aiff` | Run transcribe → clean on an audio file and print both outputs. Without `AUDIO`, synthesises a sample with `say` |
| `make uninstall` | Quit and remove the app. Models stay cached; `make models-clean` deletes them |
| `make release-dry` | Build, sign and zip the app; print the sha256 |
| `make release` | Tag, build, publish to GitHub Releases, bump the Homebrew cask |
| `make icon` | Regenerate `Resources/Talkie.icns` |

### Code signing and permissions

`scripts/build-app.sh` signs with an "Apple Development" certificate if one
is in the keychain (`TALKIE_SIGN_ACCOUNT` picks between several,
`TALKIE_SIGN_IDENTITY` names one outright), otherwise ad-hoc. macOS ties the
Microphone and Accessibility grants to the signature, and an ad-hoc signature
changes on every build, so without a certificate you are re-prompted after
each rebuild. Create one in Xcode → Settings → Accounts → Manage Certificates.

### Releasing

Versions live in `version.env`; notes live in `CHANGELOG.md`. To cut a
release: move the notes from `Unreleased` under a `## x.y.z - date` heading,
bump `version.env`, commit, then `make release-dry` to check and `make
release` to publish. The script signs with a "Developer ID Application"
certificate and notarises when one is present (set `TALKIE_NOTARY_PROFILE` to
a `notarytool` keychain profile), otherwise it signs with Apple Development or
ad-hoc and warns that users need `--no-quarantine`. It then tags `vx.y.z`,
creates the GitHub release with the zip, and updates `Casks/talkie.rb` in
`ajmccall/homebrew-tap` (cloned to `../homebrew-tap` if missing). CI
(`.github/workflows/build.yml`) builds, tests and uploads an ad-hoc zip as an
artifact on every push.

### Tuning

- `Sources/Talkie/Cleaner.swift`: cleanup prompt, sampling parameters, model
  choice (`LLMRegistry.qwen3_4b_4bit`), and the sanity check.
- `Sources/Talkie/Transcriber.swift`: Parakeet version. `.v2` is English-only
  and marginally better on English; `.v3` adds 24 more languages.
- `Sources/Talkie/TextRules.swift`: deterministic rules applied after the
  model. Add vocabulary substitutions or formatting rules there.
- `Sources/Talkie/Providers/`: the model-account protocol, the Codex and
  Claude Code implementations (CLI search order, sandbox flags, environment
  scrubbing) and the skill prompt wrapper.
- `Sources/Talkie/SkillPicker.swift`: the Fn+Shift picker panel, its keys and
  look; `SkillList` and `PickerNavigation` hold the pure logic.
- `Sources/Talkie/Sounds.swift`: the sound themes as lists of notes
  (frequency, decay, partials) rendered by `ToneSynth`.
- `Sources/Talkie/WelcomeWindow.swift`: the first-run checklist;
  `FnKeySetting.swift` reads and writes the Fn key preference.
- `Sources/Talkie/Settings.swift`: hold, minimum-length, maximum-length,
  cleanup and skill timeouts, and the paste delays.

### Logs

```sh
/usr/bin/log stream --info --predicate 'subsystem == "talkie"'
```

(`/usr/bin/log` rather than `log`, because zsh has a builtin of the same name.)
Transcripts are logged as private and are redacted unless you enable private
data in the logging profile.

### Layout

```
Sources/Talkie/            app code (menu bar, hotkey, audio, ASR, LLM, paste, HUD, picker, welcome)
Sources/Talkie/Providers/  optional skill post-processing via a connected CLI (Codex, Claude Code)
Tests/TalkieTests/         unit tests for the pure helpers
Resources/                 Info.plist, app icon
scripts/                   build-app.sh, setup.sh, release.sh, build-icon.sh
version.env, CHANGELOG.md  version and release notes
docs/REVIEW.md             code review notes and known limitations
```

## Licence

MIT. See `LICENSE`. Model and library licences are listed in the table above.
