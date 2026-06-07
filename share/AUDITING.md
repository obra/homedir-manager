# Auditing your content repos

Your content repos are marker-tagged and deploy across your machines. Run an audit periodically —
and always before pushing something new — to catch the things that rot silently: a leaked secret,
a config that drifted out of deployment, a machine that fell behind.

## The mechanical part: `homedir-manager audit`

`homedir-manager audit` automates the checks that don't need judgement:

```sh
homedir-manager audit
```

It checks, across **all** managed repos:

1. **Secret leaks** — scans every *tracked* file for credential shapes that must never be
   committed: private keys, `ops_…` (1Password service-account tokens), `ghp_…`/`github_pat_…`,
   `sk-…`, `xox?-…`, `AKIA…`, and suspicious tracked filenames (`.env`, `*.pem`, `*.key`,
   `credentials`). The scan runs `git grep -nIE -e <patterns>`, excluding `docs/*`. Any hit means
   **investigate and rotate** — a value in git history is burned even after deletion.
2. **Deploy drift** — every manifest entry (for this OS) exists in the repo and is actually
   symlinked into `$HOME`. Catches "added to the manifest but never ran `homedir-manager install`"
   and broken links.
3. **Permissions** — the files listed in `HM_SECRET_FILES` in each repo's `.homedir-manager.conf`
   marker are `600`.

Exit status is `0` clean / `1` with findings, so it drops into a pre-push hook or CI.

## The judgement part (do this by eye, ~quarterly)

The script can't decide these — walk them manually:

- **Coverage.** The universe to sweep is wider than `~/.config`: top-level `~/.*` (files **and**
  dirs), `~/.config/*`, **and** `~/Library/Application Support/*` (macOS app config — already
  tracked for some editors). For each location, reach a recorded decision: track it (public or
  private), deliver its secret via fnox, or skip it with a reason (tool-managed state, caches,
  or a credential file). A recorded decision per location is what makes "did we cover everything?"
  answerable instead of a guess — and the answer is only honest at the granularity you inspected
  (a directory marked "skip" can still grow a new config file later).
- **Content review before a *public* repo (a secret scan is NOT sufficient).** Before any file is
  tracked into a public content repo, **read it in full.** The `audit` secret-scan above catches
  credential *shapes*; it does **not** catch private/work project names, client or org identifiers,
  internal hostnames, absolute `/Users/...` paths, or journal references. None of those are secrets
  by regex, yet none belongs in a public repo. Classifying a file as public by grep alone is how
  private history leaks — judge by reading, not by pattern-matching.
- **Secret hygiene.** Confirm every secret a tool needs comes from a password manager, not a
  plaintext file. See [SECRETS.md](SECRETS.md). Any new plaintext credential found in `$HOME`
  should be moved into a manager and quarantined.
- **Host consistency.** Every machine on the same `HEAD`, same login shell, secrets resolving.
  Quick check from one host:
  ```sh
  for h in <host> …; do ssh "$h" 'git -C ~/git/<repo> rev-parse --short HEAD'; done
  ```
- **Skills/agents drift.** Agent skill dirs (`~/.claude/skills`, `~/.codex/skills`, …) hold a mix
  of repo-managed and per-host skills. Two ways to track them: list each skill as its own manifest
  entry, or use a single `merge-children` entry for the directory so new skills are picked up
  automatically while unmanaged siblings (project-linked symlinks, host-local skills) are left
  alone. If a host grew a new standalone skill worth keeping, fold it into the repo; project-linked
  skills are intentionally per-host.

## When the audit finds a leak

1. Do **not** just delete the line — the value is already in history. Rotate the credential at its
   source first.
2. Remove it from the working tree, move the real value into a manager (SECRETS.md), and add the
   path/pattern to `.gitignore`.
3. If it was ever pushed, treat it as fully compromised regardless of later history rewrites.
