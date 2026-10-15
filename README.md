# Talkie

**Hold Fn, talk, let go.** Talkie transcribes what you said on-device, tidies
it up with a small local language model, and pastes it wherever your cursor
is. No accounts, no cloud, no subscription.

## Install

Apple silicon Mac, macOS 15 or later. The speech models (about 2.6 GB) download
once on first launch.

```sh
brew install --cask ajmccall/tap/talkie
xattr -dr com.apple.quarantine /Applications/Talkie.app
```

Or download the zip from [Releases](https://github.com/ajmccall/talkie/releases),
drag `Talkie.app` to Applications, and run the same `xattr` line once.

The second line is needed because Talkie is not yet notarised, so Gatekeeper
calls a downloaded copy "damaged" until the quarantine flag is removed.
System Settings → Privacy & Security → "Open Anyway" does the same job.

Update with `brew upgrade --cask talkie`.

## First run

Talkie lives in the menu bar and opens a Welcome window with a checklist:

1. **Microphone**: allow.
2. **Accessibility**: allow. This covers both noticing Fn system-wide and
   sending ⌘V.
3. **Fn key set to "Do Nothing"**: click "Set it". Otherwise macOS also opens
   Dictation or the emoji picker on every press.
4. **Speech models**: download once; the window shows progress.

When the status reads "Ready. Hold Fn to dictate", you are done.

## Use it

Put the cursor where you want text, hold **Fn**, speak, let go. A small pill
shows "Listening…", then "Transcribing…", then the text is pasted.

Everything else is optional and described in the [guide](docs/GUIDE.md):

- **Vocabulary**: names Parakeet mis-hears, matched by sound rather than
  find-and-replace. **Fix Last Dictation** adds one from the last transcript
  in two clicks.
- **Skills** (Fn+Shift): send one dictation through a `SKILL.md` using a Codex
  or Claude Code login you already have, for example to reword it for Slack.
- **Sounds**: a few quiet synthesised themes, or off.

## How it works

| Stage | What runs | Where it comes from |
|---|---|---|
| Hotkey | `NSEvent` flags-changed monitor on the Fn key | built in |
| Capture | `AVAudioEngine` input tap, mono float samples | built in |
| Transcribe | NVIDIA Parakeet TDT 0.6B v3, Core ML, via [FluidAudio](https://github.com/FluidInference/FluidAudio) (Apache 2.0) | `FluidInference/parakeet-tdt-0.6b-v3-coreml` on Hugging Face |
| Vocabulary | Parakeet CTC 110M keyword spotting, via FluidAudio; only when the list is non-empty | `FluidInference/parakeet-ctc-110m-coreml` on Hugging Face |
| Clean up | Qwen3 4B, 4-bit, via [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) (MIT) | `mlx-community/Qwen3-4B-4bit` on Hugging Face |
| Paste | Text goes on the clipboard, then a synthetic ⌘V is sent | built in |

Audio and text never leave the Mac and are not written to disk. The one
exception is a skill run, which sends the cleaned text to the CLI you
connected, under your own login. On an M-series Mac, 8 seconds of speech
transcribes in about 0.1 s and cleans up in about 0.7 s.

## Contributing

[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) covers building from source and
releasing. [docs/REVIEW.md](docs/REVIEW.md) lists the deliberate choices and
known limitations.

## Licence

MIT. See `LICENSE`. Model and library licences are in the table above.
