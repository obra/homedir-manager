---
name: managing-homedir
description: Use when adding, changing, deploying, onboarding, or auditing homedir-manager content repos — the marker-based symlink deployment system that manages dotfiles and config across your machines. Covers the update workflow, the manifest, OS-splitting, secrets, new-machine onboarding, and the audit process.
---

# Managing homedir-manager content repos

One or more content repos, each opting in with a `.homedir-manager.conf` marker file. The engine
discovers every immediate subdirectory of `~/git` (override with `$HOMEDIR_MANAGER_BASE`) that
contains this marker and treats it as a managed repo.

Each repo has a `manifest` (`<repo-relative path> [macos|linux]`) and `homedir-manager install`
symlinks each entry into `$HOME`, backing up anything it replaces to `~/.dotfiles-backup/<ts>/`.

## Updating (the common case)

Files in `$HOME` are symlinks into the repo, so **edit in place, then `git commit`.** That's it —
the change is already live. You only run `homedir-manager install` after adding a **new** manifest
entry or on a new machine. Commit + push, then `git pull` on the other hosts.

## Adding a new config

1. Move the file into the repo at its `$HOME`-relative path (e.g. `~/.config/foo/bar` →
   `.config/foo/bar`).
2. Add the path to `manifest` — append ` macos` or ` linux` if it's OS-specific.
3. Run `homedir-manager install` (symlinks it; backs up the original).
4. Commit. `$HOME`-ize any absolute paths inside the file so it's portable.

## OS-specific config

Prefer **separate files** chosen by the manifest tag (`.config/zsh/macos.zsh` vs `linux.zsh`,
`.ssh/config.d/macos.conf`) over in-file `uname` branches. The common file sources the OS file only
if present, so it's a no-op on the other OS. Guard tool integrations with `command -v`.

## Secrets

Never commit a value. Tools get secrets lazily via `fnox` (`share/SECRETS.md`): `op` (1Password,
work) + `bw` (Bitwarden, personal), with Bitwarden unlocked silently from 1Password via `bw-unlock`.
Headless machines (no 1Password app) use a **service-account token** in `~/.config/op/env` (600,
untracked) — see SECRETS.md "Headless / unattended machines". When handling a secret value in the
shell, only ever pipe it to `wc -c` or `shasum` — never echo it, never `2>&1`/`-v`/`--full`.

## Onboarding a new machine

1. Clone your content repos into `~/git`. (Linux/headless: register an ssh key with GitHub if needed.)
2. Add `.homedir-manager.conf` to each repo if not already present (presence alone is enough).
3. Install the toolchain as needed (e.g. `mise`, `fnox`, `op`, `bw`, `jq`, `zsh`).
4. Run `homedir-manager install` to symlink everything into `$HOME`.
5. Headless secrets: mint a per-box 1Password service account, drop the token in `~/.config/op/env`
   (route it only through a temp file / `$(cat …)`, never echo), then verify the chain.

## Claude config (.claude/)

`CLAUDE.md`, `commands/`, and **standalone** skills under `.claude/skills/` can be versioned via
individual manifest entries and symlinked into `~/.claude/`. This keeps host-specific
**project-linked** skills (a `~/.claude/skills/<x>` that symlinks into a project repo) untouched. To
version a new standalone skill: drop it in `.claude/skills/<name>/`, add a manifest line, run
`homedir-manager install`.

## Auditing

Run `homedir-manager audit` before pushing and periodically (leak scan + deploy drift + perms). Full
process and the by-eye checks are in `share/AUDITING.md`.
