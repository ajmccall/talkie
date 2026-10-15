# Talkie, for agents

macOS menu-bar app, Swift Package (no Xcode project), AppKit. Push-to-talk
dictation: Fn → `AVAudioEngine` → Parakeet (FluidAudio, Core ML) → Qwen3 4B
(mlx-swift-lm) → clipboard + synthetic ⌘V. Optional Fn+Shift sends the text
through a `SKILL.md` via the user's Codex or Claude Code CLI.

Read for: user-facing behaviour, [README.md](README.md) and
[docs/GUIDE.md](docs/GUIDE.md); building, signing and releasing,
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md); why a thing is the way it is, or
whether a bug is a known limitation, [docs/REVIEW.md](docs/REVIEW.md).

## Working here

- `make test` runs the unit tests: pure helpers only, no UI, no models.
  `make selftest` runs transcribe → clean end to end on an audio file and
  needs the models downloaded. Targets are listed at the top of the Makefile.
- Building needs full Xcode with the Metal toolchain. `swift build` under the
  Command Line Tools alone fails inside MLX.
- Use `make install`, not `make run`, when testing anything that needs
  Microphone or Accessibility: an ad-hoc signature changes per build and
  macOS drops the grants with it.
- Logs: `/usr/bin/log stream --info --predicate 'subsystem == "talkie"'`.
  The full path matters in zsh. Transcripts are logged as private.
- Swift 5 language mode on purpose: Swift 6 strict concurrency is noisy on the
  ML libraries' APIs. `Transcriber` and `Cleaner` are actors; UI is
  `@MainActor`.
- Behaviour numbers (hold, minimum and maximum length, timeouts, paste delays)
  live in `Settings.swift`, each with the reason for its value in the doc
  comment. Changing one means also changing "Behaviour details" in
  `docs/GUIDE.md`.
- Every user-visible change gets a line under `Unreleased` in `CHANGELOG.md`.
  The release script turns the top dated section into the release notes and
  refuses to run while `Unreleased` is non-empty.
- `scripts/skill-timing.sh` makes real API calls on the user's login. Ask
  before running it.
- Comments and docs are written in British English, in full sentences, with
  the reason beside the rule. Match that.

## Map

`Sources/Talkie/`

- `main.swift`, `AppDelegate.swift`: menu bar, menu items, windows.
- `Controller.swift`: the dictation state machine. Owns the pipeline, the
  fallbacks (raw transcript when Qwen3 fails, cleaned transcript when a skill
  fails) and `lastDictation`, the one recording kept in memory.
- `FnKeyMonitor.swift`: global `NSEvent` monitor on key code 63. Restarted
  by `Controller` when the Accessibility grant lands, because a monitor
  created before the grant never receives events.
- `FnKeySetting.swift`: reads and writes the "Press 🌐 key to" preference.
- `AudioRecorder.swift`: `AVAudioEngine` tap, mono float samples.
- `Transcriber.swift`: Parakeet via FluidAudio (`.v2` is English-only and
  marginally better on English; `.v3` adds 24 languages) and the vocabulary
  pass with the CTC model. FluidAudio's spotter "rescue" is switched off
  there: with a short list of names it replaced ordinary phrases ("it seems")
  with names. The other knobs are in FluidAudio's
  `Documentation/ASR/CustomVocabulary.md`.
- `Vocabulary.swift`, `VocabularyWindow.swift`: term validation and storage,
  the hint line shown to Qwen3, and writing fixes back into the transcript.
- `Correction.swift`, `CorrectionWindow.swift`, `FlowLayout.swift`: Fix Last
  Dictation.
- `Cleaner.swift`: Qwen3 prompt, sampling, model id
  (`LLMRegistry.qwen3_4b_4bit`) and `looksSane`, which rejects output that
  answered instead of edited. A new `ChatSession` per dictation so no history
  bleeds between them.
- `TextRules.swift`: deterministic formatting rules applied after the model.
  New formatting rules go here, not in the prompt.
- `Paster.swift`: clipboard then ⌘V. The clipboard is left holding the text
  on purpose.
- `HUD.swift`, `RecordingLabel.swift`: the pill and its countdown text.
- `SkillPicker.swift`: the Fn+Shift picker panel. `SkillList` and
  `PickerNavigation` hold the pure logic and are what the tests cover.
- `Providers/`: `ModelProvider` protocol; `CodexProvider` and
  `ClaudeProvider` (CLI search order, sandbox flags, environment scrubbing);
  `SkillPrompt`, the wrapper that treats the transcript as data, forbids
  questions and tools, and asks for JSON.
- `Sounds.swift`: themes as lists of notes rendered by `ToneSynth`.
- `WelcomeWindow.swift`: the first-run checklist.
- `Settings.swift`: `UserDefaults` keys and the tunable constants.
- `SelfTest.swift`: the `--selftest` CLI path behind `make selftest`.
- `Subprocess.swift`, `Timeout.swift`, `TalkieError.swift`: helpers.

`Tests/TalkieTests/`: one file per pure-helper area.
`scripts/`: setup, build-app (signing), release, build-icon, skill-timing.
`Resources/`: Info.plist and icon. `version.env`: the version the release
script reads.
