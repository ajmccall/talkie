# Changelog

Notable changes, newest first. The top dated section becomes the GitHub
release notes when `scripts/release.sh` runs; `Unreleased` must be empty then.

## Unreleased

### Changed
- Fn+Shift is quicker: the highlighted skill starts the moment transcription finishes instead of after Enter, Qwen3 cleanup runs alongside it as the fallback rather than ahead of it, and the Claude Code CLI is launched while you are still speaking so its start-up is hidden.
- Claude Code skills default to `haiku` with low effort; a **Model** submenu offers `sonnet` and `opus`. A model chosen earlier is kept.

### Added
- `scripts/skill-timing.sh` to measure cold versus pre-warmed skill runs.

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
