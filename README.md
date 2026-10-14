# Talkie

Hold the Fn key, talk, let go. Talkie transcribes what you said on-device,
tidies it up with a small local language model, and pastes it wherever your
cursor is. No accounts, no cloud, no subscription. Optionally, hold Shift as
well to send that dictation through a skill using your own Codex subscription
(see [Skills](#skills-optional-uses-your-model-subscription)).

## How it works

| Stage | What runs | Where it comes from |
|---|---|---|
| Hotkey | `NSEvent` flags-changed monitor on the Fn key (key code 63) | built in |
| Capture | `AVAudioEngine` input tap, mono float samples | built in |
| Transcribe | NVIDIA Parakeet TDT 0.6B v3, Core ML, via [FluidAudio](https://github.com/FluidInference/FluidAudio) (Apache 2.0) | `FluidInference/parakeet-tdt-0.6b-v3-coreml` on Hugging Face |
| Clean up | Qwen3 4B, 4-bit, via [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) (MIT) | `mlx-community/Qwen3-4B-4bit` on Hugging Face |
| Paste | Text goes on the clipboard, then a synthetic ⌘V is sent | built in |

Both models download on first launch (roughly 0.5 GB for Parakeet and 2.5 GB
for Qwen3) and are cached under `~/Library/Application Support/FluidAudio` and
`~/.cache/huggingface`. After that, nothing leaves the machine.

On an M-series Mac, 8 seconds of speech transcribes in about 0.1 s and cleans
up in about 0.7 s.

## Requirements

- Apple silicon Mac, macOS 15 or later
- Full Xcode 26 or later (the Command Line Tools alone are not enough: MLX
  needs the Metal compiler, which only ships with Xcode), with the Metal
  Toolchain component (the setup script installs it if missing). If Xcode is
  absent, the setup script offers to install it with
  [xcodes](https://github.com/XcodesOrg/xcodes); you will be asked for your
  Apple ID and it downloads about 3 GB.
- About 4 GB of disk for models and build output

## Setting up on a new machine

```sh
git clone <this repo> talkie
cd talkie
make setup
```

`make setup` runs `scripts/setup.sh`, which checks the toolchain, downloads the
Metal Toolchain if needed, sets the Fn key to "Do Nothing" in System Settings,
builds, installs to `/Applications/Talkie.app`, and launches. Pass
`--no-fn` or `--no-install` to `scripts/setup.sh` to skip those steps.

Then, in the dialogs macOS shows:

1. **Microphone**: allow.
2. **Accessibility**: allow. This one permission covers both watching the Fn
   key system-wide and sending ⌘V. Talkie notices the grant within a couple of
   seconds; no relaunch needed. Until then it copies text but cannot paste.
3. Wait for the menu-bar icon to stop showing a download arrow.

### Why the Fn key setting matters

By default macOS binds Fn to Dictation or the emoji picker. With that on, every
press would also trigger the system feature. The setup script runs
`defaults write com.apple.HIToolbox AppleFnUsageType -int 0`; you can do the
same in System Settings → Keyboard → "Press 🌐 key to".

### Code signing and permissions

`scripts/build-app.sh` signs with the "Apple Development" certificate for
the personal Apple ID (`alasdair.mccall@gmail.com`, override with
`TALKIE_SIGN_ACCOUNT`), falling back to any Apple Development identity, then
ad-hoc. Set `TALKIE_SIGN_IDENTITY` to a certificate hash to choose explicitly.
Commits in this repo use the same personal email via the repo-local git
config (`git config user.email`), which is not committed; set it again after
cloning on another machine. macOS
ties the Microphone and Accessibility grants to the signature, and an ad-hoc
signature changes on every build, so on a machine without a development
certificate you will be re-prompted after each rebuild. Create one in Xcode →
Settings → Accounts → Manage Certificates.

## Day to day

| Command | What it does |
|---|---|
| `make install` | Rebuild, replace `/Applications/Talkie.app`, relaunch |
| `make run` | Rebuild and launch from `./build` without installing |
| `make test` | Unit tests for the pure text helpers |
| `make selftest AUDIO=file.aiff` | Run transcribe → clean on an audio file and print both outputs. Without `AUDIO`, synthesises a sample with `say` |
| `make uninstall` | Quit and remove the app. Models stay cached; `make models-clean` deletes them |

Menu-bar items: toggle the Qwen3 cleanup (raw Parakeet text is pasted when
off), the skills section (connect a model account, choose a skill), Launch at
Login, Retry Loading Models (shown after a failure), and shortcuts to the
relevant privacy settings.

## Skills (optional, uses your model subscription)

Fn alone is the whole product and never leaves the machine. Optionally, you
can connect a model account and choose a skill, and then holding **Shift** at
any point while Fn is held sends that one dictation through the skill before
it is pasted. The immediate use is the Slack reword skill, but any SKILL.md
whose job is to rewrite text will do.

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

## Tuning

- `Sources/Talkie/Cleaner.swift`: cleanup prompt, sampling parameters, model
  choice (`LLMRegistry.qwen3_4b_4bit`), and the sanity check.
- `Sources/Talkie/Transcriber.swift`: Parakeet version. `.v2` is English-only
  and marginally better on English; `.v3` adds 24 more languages.
- `Sources/Talkie/TextRules.swift`: deterministic rules applied after the
  model. Add vocabulary substitutions or formatting rules there.
- `Sources/Talkie/Providers/`: the model-account protocol, the Codex
  implementation (CLI search order, sandbox flags, environment scrubbing) and
  the skill prompt wrapper.
- `Sources/Talkie/SkillPicker.swift`: the Fn+Shift picker panel, its keys and
  look; `SkillList` and `PickerNavigation` hold the pure logic.
- `Sources/Talkie/Sounds.swift`: the sound themes as lists of notes
  (frequency, decay, partials) rendered by `ToneSynth`.
- `Sources/Talkie/Settings.swift`: hold, minimum-length, maximum-length,
  cleanup and skill timeouts, and the paste delays.

## Logs

```sh
/usr/bin/log stream --info --predicate 'subsystem == "talkie"'
```

(`/usr/bin/log` rather than `log`, because zsh has a builtin of the same name.)
Transcripts are logged as private and are redacted unless you enable private
data in the logging profile.

## Layout

```
Sources/Talkie/      app code (menu bar, hotkey, audio, ASR, LLM, paste, HUD)
Sources/Talkie/Providers/  optional skill post-processing via a connected CLI (Codex)
Tests/TalkieTests/   unit tests for the pure helpers
Resources/           Info.plist
scripts/             build-app.sh (assemble + sign), setup.sh (new machine)
docs/REVIEW.md       code review notes and known limitations
```

## Licence

MIT. See `LICENSE`. Model and library licences are listed in the table above.
