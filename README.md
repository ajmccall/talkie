# Talkie

Hold the Fn key, talk, let go. Talkie transcribes what you said on-device,
tidies it up with a small local language model, and pastes it wherever your
cursor is. No accounts, no cloud, no subscription.

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
- Xcode 26 or later, with the Metal Toolchain component (the setup script
  installs it if missing)
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
off), Launch at Login, Retry Loading Models (shown after a failure), and
shortcuts to the relevant privacy settings.

## Behaviour details

- Presses shorter than 0.25 s, or recordings under 0.5 s, are ignored.
- Recording stops by itself after 5 minutes.
- If Qwen3 takes longer than 20 s, or returns something that is not a light
  edit (empty, more than double the length, or under a third of it), the raw
  transcript is pasted instead.
- Fn pressed while models load or the previous dictation is still processing
  shows a message and does nothing.
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
- `Sources/Talkie/Settings.swift`: hold, minimum-length, maximum-length,
  timeout and paste-delay thresholds.

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
Tests/TalkieTests/   unit tests for the pure helpers
Resources/           Info.plist
scripts/             build-app.sh (assemble + sign), setup.sh (new machine)
docs/REVIEW.md       code review notes and known limitations
```

## Licence

MIT. See `LICENSE`. Model and library licences are listed in the table above.
