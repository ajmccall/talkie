# Code review, 2026-10-14

Review of the first working version of Talkie before preparing it for a
public repository. Each finding lists severity, what was wrong, and what was
done. "Fixed" means the change is in this tree and the build, unit tests and
pipeline self-test pass afterwards.

## Fixed

### 1. Fn key stays dead after Accessibility is granted (high)
`FnKeyMonitor` installed its global `NSEvent` monitor at launch. macOS does
not deliver keyboard events to a monitor created before the Accessibility
grant, so a first-time user who clicked "Allow" saw nothing happen until they
relaunched. `Controller` now polls `AXIsProcessTrusted` every 2 s while
untrusted and calls `FnKeyMonitor.restart()` when the grant lands.

### 2. Model-load failure was terminal (high)
A network error during the first download left the app in `.failed` with no
way back except quitting. Pressing Fn now retries, a "Retry Loading Models"
menu item appears, and `load()` is idempotent so a half-loaded state is safe.

### 3. LLM could hang the pipeline (medium)
`Cleaner.clean` had no timeout. A stuck generation left the HUD on
"Cleaning up…" forever and blocked all further dictation. The call is now
wrapped in `withTimeout(seconds: 20)`; on timeout the raw transcript is
pasted and the generation task is cancelled.

### 4. No guard against the model answering instead of editing (medium)
A small instruct model can treat "what time is the meeting" as a question.
`Cleaner.looksSane(raw:cleaned:)` rejects output that is empty, more than
double the input length, or under a third of it (for inputs of six words or
more), and the raw transcript is used instead. Unit tested.

### 5. Unbounded recording (medium)
Samples accumulated for as long as Fn was held; a stuck key would grow memory
at about 190 KB/s. Recording now stops itself after
`Settings.maximumRecordingSeconds` (300 s) and processes what it has.

### 6. Data race on the audio level meter (low)
`AudioRecorder.level` was written on the real-time audio thread and read on
the main thread without synchronisation. Both now go through the existing
lock. `isRecording` is only touched on the main actor and stays unlocked.

### 7. Tap left installed if the engine failed to start (low)
`AVAudioEngine.start()` throwing left the input tap in place, so the next
`start()` would hit "tap already installed". The tap is removed on failure.

### 8. HUD appeared on the wrong display (low)
`NSScreen.main` is the screen of the key window, which an accessory app does
not have. The HUD is now placed on the screen under the pointer.

### 9. Self-test deadlocked (low, found during testing)
The `--selftest` entry point blocked the main thread on a semaphore while
model loading hopped to the main actor. It now uses `dispatchMain()` and
exits from the task.

### 10. Dependency versions floated (low)
FluidAudio and mlx-swift-lm are now pinned with `exact:` and
`Package.resolved` is committed, so another machine builds the same thing.

## Deliberate choices, not changed

- **Clipboard is overwritten and not restored.** Requested behaviour: the
  dictated text should remain on the clipboard.
- **A new `ChatSession` per dictation.** Costs a re-prefill of the ~120-token
  system prompt (tens of milliseconds) and guarantees no history bleeds
  between dictations.
- **`NSEvent` monitor rather than a `CGEventTap`.** Simpler, and a listen-only
  tap would need the same Accessibility grant anyway. A tap would let us
  swallow the Fn press so other apps never see it; not needed while the system
  Fn action is set to "Do Nothing".
- **No sandbox, no hardened runtime.** Both would complicate the global key
  monitor and MLX's Metal use for a self-built, locally run tool. Revisit if
  distributing a notarised build.
- **Swift 5 language mode.** Strict Swift 6 concurrency checking produces
  noise from the ML libraries' APIs. The app's own types are actor-isolated
  where it matters (`Transcriber`, `Cleaner` are actors; UI is `@MainActor`).

## Known limitations

- Secure Keyboard Entry (password fields, Terminal with the option on)
  blocks the synthetic ⌘V. Text is still on the clipboard.
- Keyboards without an Fn key (many third-party ones) cannot trigger Talkie.
  Making the hotkey configurable is the obvious next feature.
- The first dictation after a cold start is slower while Core ML and Metal
  warm up, even with the warm-up passes at load.
- Ad-hoc signed builds lose their permission grants on every rebuild. Use an
  Apple Development certificate.
- `Launch at Login` registers the bundle at its current path; moving the app
  afterwards breaks it. Install to `/Applications` first (`make install`).
- The GitHub Actions workflow has not been run yet; it is a best-effort
  template for a macOS runner and may need the Xcode version adjusted.

## Test coverage

- `make test`: `TextRules`, `Cleaner.stripThinking`, `Cleaner.wordCount`,
  `Cleaner.looksSane`, `withTimeout`, `ToneSynth` (note length, headroom,
  WAV header, every theme defines every cue).
- `make selftest`: full Parakeet → Qwen3 pipeline on a synthesised sentence
  with fillers and stutters. Expected output removes the fillers and keeps
  the wording.
- Manual: Fn hold/release, HUD, sounds, paste, permission flow.

## Skills (Fn+Shift)

- Skill text and the model's output are logged with `privacy: .private`, like
  transcripts. The skill file path and provider executable path are logged in
  the clear.
- Claude Code runs as `claude -p` with `--tools ""`, `--disallowedTools mcp__*`,
  `--strict-mcp-config`, `--disable-slash-commands`, `--no-session-persistence`
  and `--permission-prompts none`; the environment drops `ANTHROPIC_API_KEY`,
  `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_BASE_URL`, `ANTHROPIC_PROFILE` and
  `CLAUDE_CODE_USE_*` so the subscription login is used, and sets
  `CLAUDE_CODE_DISABLE_CLAUDE_MDS` and `CLAUDE_CODE_DISABLE_AUTO_MEMORY` so no
  project or memory files reach the prompt. `CLAUDE_CONFIG_DIR` is set only
  from the folder chosen in the menu.
- The connection check runs at launch when configured and again before a
  dictation if the last check failed; a signed-out result is surfaced in the
  HUD at paste time rather than during recording.
- The skill picker is a non-activating panel that overrides `canBecomeKey`, so
  it receives arrows, Return and Escape without activating Talkie; the app you
  dictated into stays frontmost. Losing key status (a click elsewhere) counts
  as Escape. After the picker closes, the paste waits 150 ms instead of 80 ms
  so the app underneath has its key window back before ⌘V arrives.
