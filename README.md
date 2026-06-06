# homedir-manager

A portable POSIX `sh` engine that symlink-deploys and audits your dotfiles content repos, with an
optional macOS `defaults` helper. It discovers any repo under `~/git` that contains a
`.homedir-manager.conf` marker file, reads its `manifest`, and symlinks each entry into `$HOME`.
The audit verb checks for secret leaks, deploy drift, and permission violations across all managed
repos.

## Prerequisites

- POSIX `sh` everywhere (no bash, no external deps beyond `git` and standard POSIX utilities).
- On macOS, the Swift toolchain is required only if you use the `defaults` verb.

## Quickstart

```sh
git clone https://github.com/yourname/homedir-manager ~/git/homedir-manager
cd ~/git/homedir-manager
./bootstrap
```

`bootstrap` symlinks `homedir-manager` (and the short alias `hm`) into `~/.local/bin` or
`/usr/local/bin`, and builds the macOS Swift helper if the toolchain is present.

Then, for each dotfiles repo you keep under `~/git`, add a marker file:

```sh
cp ~/git/homedir-manager/share/homedir-manager.conf.example ~/git/mydotfiles/.homedir-manager.conf
# edit as needed — presence alone is sufficient
```

Deploy and audit:

```sh
homedir-manager install
homedir-manager audit
```

## Verbs

| Command | What it does |
|---|---|
| `install [--dry-run]` | Symlink every managed repo's manifest entries into `$HOME`. Backs up anything it replaces to `~/.dotfiles-backup/<ts>/`. |
| `audit` | Scan managed repos for secret leaks, deploy drift, and bad permissions. Exit `0` = clean, `1` = findings. |
| `defaults <apply\|drift\|capture>` | Delegate to the macOS Swift helper to apply, check, or capture `defaults` preferences. macOS only. |
| `help` | Print usage. |
| `version` | Print the version string. |

## Discovery model

On each run, `homedir-manager` scans the immediate subdirectories of the base directory for a
`.homedir-manager.conf` marker file. Any directory containing the marker is treated as a managed
content repo.

- **Default base:** `~/git`
- **Override:** set `$HOMEDIR_MANAGER_BASE` in your environment.

## The `.homedir-manager.conf` marker

Presence of the file is sufficient to opt a repo in. Optionally, set `HM_SECRET_FILES` to a
space-separated list of local files that the audit will verify are `chmod 600`:

```sh
# .homedir-manager.conf
HM_SECRET_FILES="$HOME/.config/op/env"
```

See `share/homedir-manager.conf.example` for a ready-to-copy template.

## The `manifest` format

Each line: `<repo-relative-path> [macos|linux]`

Lines with an OS tag are only deployed/audited on that OS. Blank lines and `#` comments are ignored.

## Further reading

- `share/AUDITING.md` — the full audit process and by-eye quarterly checks.
- `share/SECRETS.md` — the recommended secret management model (fnox + 1Password/Bitwarden).
- `skills/managing-homedir/SKILL.md` — operational skill for Claude Code.
