# Talkie guide

Everything beyond "hold Fn, talk, let go". Install and first run are in the
[README](../README.md).

## The menu

The menu-bar microphone holds: the Qwen3 cleanup toggle (raw transcription is
pasted when off), **Vocabulary…**, **Fix Last Dictation…**, **Sounds**, the
optional Skills section, Launch at Login, shortcuts to the relevant privacy
settings, and **Welcome / How Talkie works…** to reopen the first-run window.

## Vocabulary

**Vocabulary…** holds names and unusual words Parakeet should recognise
("Alfie", "Mindera"), each with the spellings it usually produces instead
("Alfy"). It is not a find-and-replace: Talkie listens to the recording again
with a small extra Parakeet CTC model and swaps a word only when the sound
supports it, so a list of names does not disturb ordinary speech. Bare terms
catch most mishearings; adding what Talkie writes instead catches the rest.
The same list is shown to Qwen3 so spelling and capitalisation stay
consistent, and the paste message says what was fixed ("Pasted (fixed
Alfie)").

The extra model (about 100 MB) downloads the first time a word is added and
adds roughly a tenth of a second to a short dictation. Everyday words and
anything under three letters are best left out; the window warns about the
latter.

### Fix Last Dictation

**Fix Last Dictation…** is the quick way in. It shows the last transcript as
clickable words: click the one Talkie got wrong (two adjacent words for a
longer name), type what it should have been, and Talkie adds it to the
Vocabulary with the mis-hearing as a known spelling. It then listens to that
same recording again and says whether the new spelling is picked up ("Now
hears “Alfie”") or still missed, so you know straight away rather than on
the next dictation. The recording and text are kept in memory only, until
the next dictation or quit. For the first few dictations the paste message
points at the item ("Pasted (wrong word? Fix Last Dictation in the menu)").

## Skills (Fn+Shift)

Fn alone is the whole product, needs no account, and never leaves the
machine. Optionally, connect a **Codex** or **Claude Code** login (the CLI you
already use; Talkie never sees the tokens) and choose a skill. Holding
**Shift** at any point while Fn is held sends that one dictation through the
skill before it is pasted. The immediate use is a Slack reword skill, but any
`SKILL.md` whose job is to rewrite text will do.

### Setting up

1. **Connect Codex…** or **Connect Claude Code…** in the menu. Talkie looks
   for the CLI in the usual places (the ChatGPT and Codex apps,
   `~/.local/bin`, Homebrew, and the newest nvm install) and asks it whether
   it is signed in. If not, run `codex login` or `claude auth login` in
   Terminal and use **Check Connection**. If the CLI is somewhere unusual,
   **Choose … Executable…**. One account is connected at a time; Disconnect
   and connect the other to switch.
   - Claude Code: if your login lives in a profile folder rather than
     `~/.claude` (you set `CLAUDE_CONFIG_DIR` in the shell), point Talkie at
     it with **Choose Claude Config Folder…**.
2. **Skills ▸ Add Skill…** and pick one or more `SKILL.md` files, for example
   `~/.agents/skills/slack-reword/SKILL.md`. Skills are re-read on every
   dictation, so edits apply immediately. **Skills ▸ Remove ▸** takes one out
   again; ticking an entry makes it the pre-selected skill.
3. **Model ▸** picks the model the skill runs on. Claude Code defaults to
   `haiku`, the fastest; `sonnet` and `opus` are there when the rewrite needs
   more care.

### Using it

Hold Fn and Shift, speak, release. A picker appears in place of the HUD the
moment you let go, listing your skills with the last-used one highlighted,
and shows "Transcribing…" then "Ready" while Talkie works.

- **Enter** applies the highlighted skill. You can press it before "Ready";
  it applies as soon as the text is there.
- **↑ ↓**, the mouse, or the number keys **1–9** change the highlight.
- **Escape**, or clicking into another window, pastes the transcription
  as-is.

The picker takes keyboard focus without activating Talkie, so the app you
were in stays frontmost and receives the paste. Fn does nothing while the
picker is open.

Talkie does not wait for you: the highlighted skill starts on the transcript
the instant transcription finishes, so Enter usually confirms a run already in
flight; picking a different entry cancels it and starts that one. Holding
Shift also launches the CLI while you are still speaking, so its start-up
overlaps the recording. Qwen3 cleanup runs alongside the skill and is pasted
only if the skill fails. Measured with `scripts/skill-timing.sh`, a Claude
Code skill run takes about 1.0 s on `haiku` and 1.4 s on `sonnet`; what is
left is the API call.

### What the skill sees

Talkie wraps the skill and the transcript in a prompt that treats the
transcript as data, forbids questions (the model assumes instead), forbids
tools, and asks for structured JSON. Codex runs ephemeral and read-only with
every tool disabled. Claude Code runs with `claude -p`, no tools, no hooks,
no CLAUDE.md or memory, low effort, and a JSON schema for the reply.

A failure, timeout (90 s) or bad response pastes the cleaned transcript
instead and the HUD says why, e.g. "Pasted (reword failed: signed out)".
Fn+Shift without a connected account or chosen skill pastes the cleaned
transcript and says so.

## Sounds

**Sounds ▸** picks a set of cues for start, stop, paste and failure. Soft
Chime (the default), Marimba, Muted Glass and Minimal are synthesised by
Talkie itself and kept quiet and rounded; macOS Sounds uses the bundled Tink,
Pop, Glass and Basso; Off is silent. Choosing a theme plays its "pasted"
sound, **Play Start, Stop, Pasted** runs through a whole dictation, and Quiet
halves the volume.

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
  shows a message and does nothing. While the skill picker is open, Fn shows
  "Still working on the last one…".
- The clipboard is deliberately left holding the dictated text.
- The last dictation (audio and text) stays in memory for Fix Last Dictation
  and is replaced by the next one; nothing is written to disk.
- Apps with Secure Keyboard Entry on (password fields, Terminal with the
  option enabled) swallow the synthetic ⌘V. The text is still on the clipboard.
- If a model download fails, pressing Fn retries, and a "Retry Loading
  Models" item appears in the menu.

## Models on disk

The models download on first use and are cached under
`~/Library/Application Support/FluidAudio/Models` and
`~/.cache/huggingface/hub`. Those folders are shared with other tools, so
`brew uninstall --cask talkie` leaves them alone; delete them by hand (or
`make models-clean` from a checkout) to reclaim the space.
