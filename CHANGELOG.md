# Changelog

Notable changes, newest first. The top dated section becomes the GitHub
release notes when `scripts/release.sh` runs; `Unreleased` must be empty then.

## Unreleased

## 0.3.0 - 2026-10-17

### Changed
- Fn+Shift is quicker: the highlighted skill starts the moment transcription finishes instead of after Enter, Qwen3 cleanup runs alongside it as the fallback rather than ahead of it, and the Claude Code CLI is launched while you are still speaking so its start-up is hidden.
- Claude Code skills default to `haiku` with low effort; a **Model** submenu offers `sonnet` and `opus`. A model chosen earlier is kept.

### Added
- **Fix Last Dictation…** in the menu bar: the last transcript as clickable words. Click the mis-heard word, type what it should have been, and it is added to the Vocabulary with that spelling as a known mis-hearing; Talkie then listens to the same recording again and says whether the new spelling is picked up. The recording is kept in memory only until the next dictation. The paste message points at the item for the first ten dictations.
- **Vocabulary…** window in the menu bar: names and unusual words Parakeet should recognise, each with the spellings it usually produces instead. Matching is acoustic: a small extra Parakeet CTC model (about 100 MB, downloaded when the first word is added) listens to the recording again and a word is only swapped when the sound supports it. The same list is given to Qwen3 so spelling stays consistent, and the paste message says what was fixed.
- `make selftest` accepts `VOCAB=<list file>` (one term per line, `Alfie: Alfy, Alfi`) to try the vocabulary pass on a recording.
- `scripts/skill-timing.sh` to measure cold versus pre-warmed skill runs.

### Fixed
- A skill reply could paste as raw JSON (`{"text": "…\n\n…"}`) when the model wrapped its answer twice. Talkie now unwraps it.
- Closing the skill picker without choosing now says "Pasted as-is (no skill)" instead of a plain "Pasted", so a skipped skill is visible.

## 0.2.0 - 2026-10-14

### Added
- Homebrew install (`brew install --cask ajmccall/tap/talkie`) and zip releases on GitHub.
- Welcome window on first launch: what Talkie does, permission checklist, Fn key setting, model download progress, and a note that AI accounts are optional.
- Claude Code as a second skill provider next to Codex.
- Skill picker on Fn+Shift with a menu-bar Skills list (add, remove, preselect).
- Sound themes (Soft Chime, Marimba, Muted Glass, Minimal, macOS, Off) and a Quiet volume.

## 0.1.0 - 2026-10-01

### Added
- Push-to-talk dictation: hold Fn, Parakeet transcribes on-device, Qwen3 tidies, text is pasted.
