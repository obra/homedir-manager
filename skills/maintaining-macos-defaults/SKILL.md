---
name: maintaining-macos-defaults
description: Use on demand to reconcile a Mac's GUI-changed settings into version control — when the user says "reconcile my mac defaults", "capture my macOS settings", or after they've changed System Settings and want the keepers tracked. Drives homedir-manager's `defaults` verb (capture/drift/apply) against a versioned desired-state file.
---

# Maintaining macOS defaults

Lets the user drive their Mac through the GUI like a normal person, then fold the settings worth
keeping into a version-controlled file. The judgment — signal vs. noise — is your job; the tool
just reads, diffs, and writes the macOS preferences (CFPreferences) system.

## The data (in the user's dotfiles content repo, deployed to `~/.config/macos-defaults/`)

- `desired.tsv` — the tracked settings: `domain⇥key⇥type⇥value`, sorted. Scalars only
  (bool/int/float/string). This is both what gets applied and the baseline drift diffs against.
- `watched-domains` — one domain per line; the domains `drift` scans for new settings.
- `noise-deny` — glob patterns (matched against key names) that `drift` and whole-domain
  `capture` ignore (window frames, recents, counters, timestamps).

## The on-demand loop

When the user asks to reconcile (after they've changed settings in the GUI):

1. **See what changed:**
   ```sh
   homedir-manager defaults drift ~/.config/macos-defaults/desired.tsv \
     --watched ~/.config/macos-defaults/watched-domains \
     --noise   ~/.config/macos-defaults/noise-deny
   ```
   - `DRIFT  <domain> <key> current=… desired=…` — a tracked setting whose live value changed.
   - `NEW    <domain> <key> current=…` — a setting they changed that isn't tracked yet.

2. **Triage each line.** Keep deliberate preferences; drop noise. A setting is **signal** if a
   person would knowingly choose it (`com.apple.dock autohide`, `…finder ShowPathbar`). It's
   **noise** if it's machine state: window positions, recent-item lists, counters, timestamps,
   last-opened paths, UUIDs. When unsure, lean toward *not* tracking it — and if a noise pattern
   would have caught it, add that pattern to `noise-deny` instead of rejecting it one-off.

3. **Fold keepers into `desired.tsv`** with correct types read live:
   ```sh
   homedir-manager defaults capture com.apple.dock autohide >> ~/.config/macos-defaults/desired.tsv
   ```
   Then keep the file sorted (`sort -o`). For a `DRIFT` (changed tracked value), update the
   existing line instead of appending a duplicate.

4. **Commit** the content repo. Other machines pick it up on `git pull`.

## Applying on another Mac

`apply` writes the tracked settings into the live preferences and restarts Dock/Finder/SystemUIServer:
```sh
homedir-manager defaults apply ~/.config/macos-defaults/desired.tsv
```
Only run this when the user wants that machine to match the tracked state — it changes their live
settings. Some settings need a logout to fully take effect.

## Limits

- Scalars only. Dictionary/array/date/data values are flagged (`SKIP …` on stderr), not written.
- Covers the CFPreferences surface — most of "driving your Mac," but not settings that live in
  sandboxed containers, opaque databases, or need `scutil`/`systemsetup`.
- macOS only.
