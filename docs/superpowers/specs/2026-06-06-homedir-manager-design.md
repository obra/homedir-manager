# homedir-manager — Design

**Goal:** Extract the dotfiles *management machinery* (deploy + audit + macOS defaults) out of
Jesse's content repos into a standalone, general-purpose tool that other people can adopt to
manage their own homedir config repos.

**Architecture:** A portable POSIX `sh` engine (deploy + audit) plus a vendored macOS-only Swift
helper (`macos-defaults`) it shells out to. The engine operates on a user's *content repos*
(their dotfiles), discovered by an opt-in marker file. Content and machinery are cleanly
separated: the engine carries no user-specific config or secrets.

**Tech stack:** POSIX `sh` (engine core, cross-platform), Swift + SwiftPM (macOS defaults
helper), the existing `sh` test harness.

---

## 1. Motivation

The dotfiles system today mixes three kinds of thing in one repo: actual config **content**,
runtime **helpers** that are really content (`lib/secret.sh`, personal `bin/` tools), and the
**machinery** that deploys and maintains everything (`install.sh`, `dotfiles-audit`, docs, the
`managing-dotfiles` skill). Other people are about to adopt the machinery. A tool meant for
others cannot live welded into one person's config repo, and a compiled Swift component (the new
`macos-defaults` helper) wants a real code repo with tests, not a corner of a config repo.

So: split the machinery into `homedir-manager`, leave the content in the content repos, and make
the engine operate on *any* user's content repos.

## 2. Repo topology

Three repos, split along **engine vs content**:

- **`homedir-manager`** (new, public) — the engine. Deploy logic, audit, the `macos-defaults`
  Swift helper (vendored), generic docs, the management skill, test harness, bootstrap. Carries
  nothing user-specific.
- **`dotfiles`** (existing, public) — content only: config files, `manifest`, personal `bin/`
  tools, `lib/secret.sh` (runtime helper sourced at login), real `.claude/skills/*`, and the
  macos-defaults **data** (`desired.tsv`, `watched-domains`, `noise-deny`).
- **`dotfiles-private`** (existing, private) — private content + its own `manifest`.

### The engine/content seam

- **Machinery → engine:** `install.sh`, `dotfiles-audit`, `docs/AUDITING.md`, `docs/SECRETS.md`
  (de-personalized to generic guidance), `test/`, the `managing-dotfiles` skill (rewritten as
  product docs).
- **Content stays:** `lib/secret.sh` (it is *deployed* and sourced at login — part of the user's
  environment, wired to *their* secret manager), personal `bin/` tools, all configs, macos-defaults
  data.
- **The engine is secrets-agnostic.** It ships only generic secrets guidance; a user's actual
  fnox/1Password/Bitwarden wiring stays in their content repos. No secrets abstraction is baked
  into the engine in v1.

## 3. Engine layout

```
homedir-manager/
  bin/homedir-manager     # single entry: subcommand dispatcher (sh). 'hm' alias symlink.
  lib/                    # deploy.sh, audit.sh, config.sh (discovery/resolution)
  macos/                  # vendored macos-defaults Swift package (see its own spec)
  share/                  # generic AUDITING.md, SECRETS.md, the .homedir-manager.toml template
  skills/                 # managing-homedir skill (product docs)
  test/                   # the existing sh harness + new discovery/multi-repo/audit cases
  bootstrap               # first-run: PATH wire-up, build Swift helper (macOS), optional install
  README.md
```

The executable core is `sh`; `lib/*.sh` hold the deploy, audit, and discovery logic so each is
small and independently testable.

## 4. Verbs

One entry point, `homedir-manager <verb>` (with an `hm` alias):

- **`install [--dry-run]`** — deploy every discovered content repo via its `manifest`. This is
  today's `install.sh` logic generalized to iterate over discovered repos. Per-entry idempotency
  (`-ef` check), backup-on-conflict to `~/.dotfiles-backup/<ts>/`, OS-tag filtering (`macos`/
  `linux`) unchanged.
- **`audit [-q]`** — leak scan + deploy-drift + perms, across discovered content repos. Today's
  `dotfiles-audit`, generalized: the secret-pattern scan and deploy-drift run per discovered repo;
  the hardcoded `~/.config/op/env` perms check becomes **opt-in per-repo config** declared in the
  repo's `.homedir-manager.toml` marker (e.g. a `secret_files` list), so the engine carries no
  user-specific path.
- **`defaults <apply|drift|capture> …`** — on macOS, delegates to the vendored `macos-defaults`
  binary per its fixed CLI contract, pointing it at the data files in the user's content repo. On
  Linux, exits cleanly with a "macOS only" message.
- **`--help` / `--version`.**

## 5. Discovery (convention-with-override)

- A content repo **opts in** with a marker file at its root: **`.homedir-manager.toml`**. It may
  be empty in v1; it exists to carry per-repo settings later (e.g. `secret_files` for the audit
  perms check, public/private hints). The `manifest` remains the *deploy list*. This separates
  "is this a content repo?" (marker) from "what does it deploy?" (manifest), and avoids false
  positives from an unrelated repo that happens to contain a file named `manifest`.
- **Convention:** scan a base dir (default `~/git`; override via `$HOMEDIR_MANAGER_BASE` or
  `--base`) for immediate subdirectories containing the marker → operate on all of them.
- **Override:** an explicit repo list via flag/config takes precedence over the scan.
- For Jesse, migration adds the marker to `dotfiles` and `dotfiles-private`; everything else in
  `~/git` is ignored.

## 6. The macOS defaults helper

`macos-defaults` is specified separately (built standalone, then vendored into `macos/`). See its
spec for the full contract. The engine's only coupling to it is the **stable CLI contract**:

```
macos-defaults apply  <statefile> [--no-reload]
macos-defaults drift  <statefile> [--watched <file>] [--noise <file>]
macos-defaults capture <domain> [<key>...] [--noise <file>]
```

- **Vendored**, not a separate dependency: one repo to clone, one version. `bootstrap` (and a lazy
  check before `defaults` runs) does `swift build -c release` of `macos/` and caches the binary;
  the engine locates it. Linux never builds it.
- The defaults **data** (`desired.tsv`, `watched-domains`, `noise-deny`) lives in the user's
  content repo, not the engine.

## 7. Migration (cycle 1) — 2 repos → 3, without breaking the live fleet

Deployed symlinks point at **content** (which stays in `dotfiles`), so moving machinery does not
touch them. Only two deployed items are machinery and need rehoming: `bin/dotfiles-audit` (on
PATH) and the `managing-dotfiles` skill (symlinked into `~/.claude/skills/`); the engine's
bootstrap deploys these instead.

History for the moved machinery is **not** preserved (plain move — copy into `homedir-manager`,
`git rm` from `dotfiles`; history remains in the `dotfiles` log).

Steps (done on a branch/worktree; parity validated before any deletion):

1. Scaffold `homedir-manager`; move the machinery in; generalize `install`/`audit` for
   marker-based multi-repo discovery and strip user-specific assumptions (the `op/env` perms
   check → marker config).
2. Add `.homedir-manager.toml` to `dotfiles` + `dotfiles-private`; `git rm` the moved machinery
   from `dotfiles`; drop the now-engine-owned `manifest` lines (`bin/dotfiles-audit`, the
   `managing-dotfiles` skill).
3. `bootstrap` on the **primary machine**: engine on PATH, deploys its own skill, then
   `homedir-manager install` + `audit` — **verify parity** (same symlinks resolve, audit passes)
   before deleting the old `install.sh`.
4. Roll to the other three machines: `git pull` content repos, clone + bootstrap the engine,
   `install`, `audit`.
5. **Join point with the parallel track:** once the `macos-defaults` worker lands a green build,
   vendor it into `homedir-manager/macos/`.

No backward-compat shim for the old `install.sh` invocation unless explicitly requested.

## 8. Testing

- The existing `sh` harness (`test/assert.sh`, `run.sh`, runner-guard) moves to the engine and
  grows cases for the new surface: marker-based **discovery**, **multi-repo** install, and audit.
  Runs on macOS + Linux.
- `macos-defaults` carries its own Swift test suite (macOS-only).
- Portable `sh` tests gate the core on every platform; Swift tests gate the helper on macOS.

## 9. Distribution

- v1: `git clone` + `./bootstrap`. **No Homebrew tap** yet (YAGNI; revisit if adoption warrants
  the formula + release maintenance).
- `bootstrap` detects OS, puts `homedir-manager` on PATH, builds the Swift helper on macOS, and
  offers to run `install`.
- README documents prerequisites (POSIX `sh` everywhere; Swift toolchain on macOS only for the
  `defaults` verb) and an adopter quickstart.

## 10. Non-goals (v1)

- No Homebrew tap / released binaries.
- No backward-compat shim for `./install.sh`.
- No secrets-management abstraction in the engine.
- No Go rewrite of the core (reconsider only if the engine's complexity outgrows `sh`).
- No collection-type or non-CFPreferences settings support (that's the helper's scope, also v1
  scalar-only).
