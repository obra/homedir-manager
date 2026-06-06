# homedir-manager Restructure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract the dotfiles management machinery (deploy + audit + macOS-defaults delegation) out of Jesse's `dotfiles` repo into a standalone, general-purpose `homedir-manager` engine that operates on any user's marker-tagged content repos.

**Architecture:** A portable POSIX `sh` engine: a `bin/homedir-manager` dispatcher sources small single-responsibility libs (`lib/common.sh`, `lib/config.sh`, `lib/deploy.sh`, `lib/audit.sh`, `lib/defaults.sh`). Content repos opt in with a sh-sourceable `.homedir-manager.conf` marker. The macOS `defaults` verb shells out to a vendored Swift `macos-defaults` binary (built separately, vendored at the join point). All logic is parametrized by `HOME`/`UNAME_OVERRIDE` env so the existing plain-`sh` test harness can exercise it in temp dirs.

**Tech Stack:** POSIX `sh`, the existing `test/assert.sh` + `test/run.sh` harness. Swift only at the vendoring join point (out of scope for this plan).

**Reference:** spec at `docs/superpowers/specs/2026-06-06-homedir-manager-design.md`. The source machinery to port lives in `~/git/dotfiles`: `install.sh`, `bin/dotfiles-audit`, `test/` (`assert.sh`, `run.sh`, `test_install.sh`, `test_runner_guard.sh`), `docs/AUDITING.md`, `docs/SECRETS.md`, and `.claude/skills/managing-dotfiles/`.

**Marker format decision (refines spec):** the content-repo marker is `.homedir-manager.conf`, a sh-sourceable fragment. Its *presence* marks a content repo. It may be empty, or set `HM_SECRET_FILES="<space-separated paths>"` consumed by the audit perms check. (The spec's `.homedir-manager.toml` is updated to this; TOML parsing in `sh` is not worth it.)

**Working location:** the engine repo is `~/git/homedir-manager` (already git-init'd, holds this plan + the spec). Build on a feature branch.

**Convention used throughout:** every lib is sourced, never executed. Functions read `HOME` and `UNAME_OVERRIDE` from the environment (never hardcode paths) so tests run hermetically in temp dirs. Each `test/test_*.sh` ends with `printf 'RESULT run=%s failed=%s\n' "$TESTS_RUN" "$TESTS_FAILED"`.

---

## Phase A — Engine build (TDD, subagent-driven)

### Task A1: Scaffold the engine skeleton + test harness

**Files:**
- Create: `~/git/homedir-manager/lib/common.sh`
- Create: `~/git/homedir-manager/bin/homedir-manager`
- Create: `~/git/homedir-manager/test/assert.sh` (copied from dotfiles)
- Create: `~/git/homedir-manager/test/run.sh` (copied from dotfiles)

- [ ] **Step 1: Copy the test harness verbatim from dotfiles**

```bash
cp ~/git/dotfiles/test/assert.sh ~/git/homedir-manager/test/assert.sh
cp ~/git/dotfiles/test/run.sh    ~/git/homedir-manager/test/run.sh
chmod +x ~/git/homedir-manager/test/run.sh
```

- [ ] **Step 2: Write `lib/common.sh`**

```sh
# common.sh — shared helpers for the homedir-manager engine. Sourced, never executed.

# Marker filename that opts a directory in as a managed content repo.
HM_MARKER='.homedir-manager.conf'

# os_name — map uname (overridable for tests) to macos/linux/other.
os_name() {
  case "${UNAME_OVERRIDE:-$(uname -s)}" in
    Darwin) echo macos ;;
    Linux)  echo linux ;;
    *)      echo other ;;
  esac
}

# hm_die — print to stderr and exit non-zero.
hm_die() { printf 'homedir-manager: %s\n' "$1" >&2; exit "${2:-1}"; }
```

- [ ] **Step 3: Write a minimal `bin/homedir-manager` dispatcher (verbs stubbed)**

```sh
#!/bin/sh
# homedir-manager — deploy + audit + macOS-defaults for marker-tagged content repos.
set -eu

# shellcheck disable=SC1007
HM_LIB=$(CDPATH= cd -- "$(dirname -- "$0")/../lib" && pwd -P)
. "$HM_LIB/common.sh"

usage() {
  cat <<'EOF'
usage: homedir-manager <command> [options]

commands:
  install [--dry-run]              symlink every managed repo's manifest into $HOME
  audit [-q]                       scan managed repos for leaks, drift, bad perms
  defaults <apply|drift|capture> … macOS preferences (macOS only)
  help | --help                    this message
  version | --version              print version
EOF
}

HM_VERSION='0.1.0'

cmd=${1:-help}
[ "$#" -gt 0 ] && shift || true
case "$cmd" in
  help|--help|-h) usage ;;
  version|--version) printf '%s\n' "$HM_VERSION" ;;
  install) hm_die "install not yet implemented" ;;
  audit)   hm_die "audit not yet implemented" ;;
  defaults) hm_die "defaults not yet implemented" ;;
  *) usage; exit 2 ;;
esac
```

```bash
chmod +x ~/git/homedir-manager/bin/homedir-manager
```

- [ ] **Step 4: Smoke test — version and help work**

Run:
```bash
~/git/homedir-manager/bin/homedir-manager version
~/git/homedir-manager/bin/homedir-manager help
```
Expected: prints `0.1.0`; prints the usage block. Exit 0 both.

- [ ] **Step 5: Commit**

```bash
cd ~/git/homedir-manager && git add -A
git commit -m "Scaffold homedir-manager engine skeleton + test harness"
```

---

### Task A2: Content-repo discovery (`lib/config.sh`)

**Files:**
- Create: `~/git/homedir-manager/lib/config.sh`
- Test: `~/git/homedir-manager/test/test_config.sh`

- [ ] **Step 1: Write the failing test**

```sh
#!/bin/sh
set -u
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
LIB=$(CDPATH= cd -- "$HERE/../lib" && pwd -P)
. "$HERE/assert.sh"
. "$LIB/common.sh"
. "$LIB/config.sh"

# hm_base honors override, defaults to $HOME/git
out=$(HOMEDIR_MANAGER_BASE=/tmp/xyz hm_base); assert_eq "/tmp/xyz" "$out" "base honors override"
out=$(HOME=/home/zz hm_base); assert_eq "/home/zz/git" "$out" "base defaults to \$HOME/git"

# discover_repos finds only dirs containing the marker, as physical paths, sorted
TMP=$(mktempd)
mkdir -p "$TMP/a" "$TMP/b" "$TMP/c"
: > "$TMP/a/$HM_MARKER"        # a is managed
: > "$TMP/c/$HM_MARKER"        # c is managed; b is not
: > "$TMP/b/manifest"         # b has a manifest but no marker -> ignored
got=$(discover_repos "$TMP" | sed "s#$TMP/##" | tr '\n' ',')
assert_eq "a,c," "$got" "discovers only marker dirs, sorted, excludes bare-manifest dir"
rm -rf "$TMP"

printf 'RESULT run=%s failed=%s\n' "$TESTS_RUN" "$TESTS_FAILED"
```

- [ ] **Step 2: Run it, expect failure**

Run: `sh ~/git/homedir-manager/test/test_config.sh`
Expected: FAIL / crash — `config.sh` and its functions don't exist yet.

- [ ] **Step 3: Implement `lib/config.sh`**

```sh
# config.sh — locate managed content repos. Sourced, never executed.
# Depends on common.sh (HM_MARKER).

# hm_base — base directory scanned for managed repos.
hm_base() { printf '%s\n' "${HOMEDIR_MANAGER_BASE:-$HOME/git}"; }

# discover_repos [base] — print the physical path of each immediate subdirectory
# of base that contains the marker file, one per line, in sorted glob order.
discover_repos() {
  base=${1:-$(hm_base)}
  [ -d "$base" ] || return 0
  for d in "$base"/*/; do
    [ -f "$d$HM_MARKER" ] || continue
    (CDPATH= cd -- "$d" && pwd -P)
  done
}
```

- [ ] **Step 4: Run the test, expect pass**

Run: `sh ~/git/homedir-manager/test/test_config.sh`
Expected: `RESULT run=4 failed=0`.

- [ ] **Step 5: Commit**

```bash
cd ~/git/homedir-manager && git add -A
git commit -m "Add marker-based content-repo discovery (lib/config.sh)"
```

---

### Task A3: Deploy engine (`lib/deploy.sh`) — port + generalize install.sh

**Files:**
- Create: `~/git/homedir-manager/lib/deploy.sh`
- Test: `~/git/homedir-manager/test/test_deploy.sh`

The current `~/git/dotfiles/install.sh` resolves its own dir as `REPO_DIR` and links one manifest. Generalize: a `deploy_repo <repo_dir> [--dry-run]` function takes the repo as an argument, preserving the exact link/backup/idempotency/`-ef` semantics (and the OS-tag manifest filter).

- [ ] **Step 1: Write the failing test (ports the install.sh behaviors to deploy_repo)**

```sh
#!/bin/sh
set -u
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
LIB=$(CDPATH= cd -- "$HERE/../lib" && pwd -P)
. "$HERE/assert.sh"
. "$LIB/common.sh"
. "$LIB/deploy.sh"

# OS-tag filtering via deploy_repo --dry-run
TMP=$(mktempd); mkdir -p "$TMP/repo" "$TMP/home"
: > "$TMP/repo/common.conf"; : > "$TMP/repo/maconly.conf"; : > "$TMP/repo/linonly.conf"
cat > "$TMP/repo/manifest" <<'EOF'
# a comment
common.conf
maconly.conf   macos
linonly.conf   linux
EOF
out=$(UNAME_OVERRIDE=Darwin HOME="$TMP/home" deploy_repo "$TMP/repo" --dry-run)
echo "$out" | grep -q 'common.conf'  && c=yes || c=no
echo "$out" | grep -q 'maconly.conf' && m=yes || m=no
echo "$out" | grep -q 'linonly.conf' && l=yes || l=no
assert_eq "yes" "$c" "common.conf included on macOS"
assert_eq "yes" "$m" "maconly.conf included on macOS"
assert_eq "no"  "$l" "linonly.conf excluded on macOS"
rm -rf "$TMP"

# dry-run makes no changes
TMP=$(mktempd); mkdir -p "$TMP/repo" "$TMP/home"; : > "$TMP/repo/common.conf"
printf 'common.conf\n' > "$TMP/repo/manifest"
UNAME_OVERRIDE=Darwin HOME="$TMP/home" deploy_repo "$TMP/repo" --dry-run >/dev/null
if [ ! -e "$TMP/home/common.conf" ] && [ ! -L "$TMP/home/common.conf" ]; then z=absent; else z=present; fi
assert_eq "absent" "$z" "dry-run creates nothing"
rm -rf "$TMP"

# real link, real parent dir
TMP=$(mktempd); mkdir -p "$TMP/repo/sub" "$TMP/home"; echo hi > "$TMP/repo/sub/n.conf"
printf 'sub/n.conf\n' > "$TMP/repo/manifest"
UNAME_OVERRIDE=Darwin HOME="$TMP/home" deploy_repo "$TMP/repo" >/dev/null
assert_symlink_to "$TMP/home/sub/n.conf" "$TMP/repo/sub/n.conf" "nested file linked"
if [ -d "$TMP/home/sub" ] && [ ! -L "$TMP/home/sub" ]; then p=real; else p=notreal; fi
assert_eq "real" "$p" "parent dir is real"
rm -rf "$TMP"

# idempotency: second run links nothing, no backup dir
TMP=$(mktempd); mkdir -p "$TMP/repo" "$TMP/home"; echo x > "$TMP/repo/a.conf"
printf 'a.conf\n' > "$TMP/repo/manifest"
UNAME_OVERRIDE=Darwin HOME="$TMP/home" deploy_repo "$TMP/repo" >/dev/null
out2=$(UNAME_OVERRIDE=Darwin HOME="$TMP/home" deploy_repo "$TMP/repo")
echo "$out2" | grep -q 'linked=0' && zz=yes || zz=no
assert_eq "yes" "$zz" "second run idempotent"
if [ -d "$TMP/home/.dotfiles-backup" ]; then b=exists; else b=absent; fi
assert_eq "absent" "$b" "no backup on idempotent re-run"
rm -rf "$TMP"

# broken symlink replaced
TMP=$(mktempd); mkdir -p "$TMP/repo" "$TMP/home"; echo r > "$TMP/repo/x.conf"
printf 'x.conf\n' > "$TMP/repo/manifest"
ln -s "$TMP/home/missing" "$TMP/home/x.conf"
UNAME_OVERRIDE=Darwin HOME="$TMP/home" deploy_repo "$TMP/repo" >/dev/null
assert_symlink_to "$TMP/home/x.conf" "$TMP/repo/x.conf" "broken link replaced"
rm -rf "$TMP"

# conflict: real file backed up, content preserved
TMP=$(mktempd); mkdir -p "$TMP/repo" "$TMP/home"; echo from-repo > "$TMP/repo/c.conf"
echo pre-existing > "$TMP/home/c.conf"
printf 'c.conf\n' > "$TMP/repo/manifest"
UNAME_OVERRIDE=Darwin HOME="$TMP/home" deploy_repo "$TMP/repo" >/dev/null
assert_symlink_to "$TMP/home/c.conf" "$TMP/repo/c.conf" "conflict replaced by symlink"
found=$(find "$TMP/home/.dotfiles-backup" -name c.conf -exec cat {} \; 2>/dev/null)
assert_eq "pre-existing" "$found" "original content preserved in backup"
rm -rf "$TMP"

printf 'RESULT run=%s failed=%s\n' "$TESTS_RUN" "$TESTS_FAILED"
```

- [ ] **Step 2: Run it, expect failure**

Run: `sh ~/git/homedir-manager/test/test_deploy.sh`
Expected: FAIL / crash — `deploy.sh` doesn't exist.

- [ ] **Step 3: Implement `lib/deploy.sh`** (port of install.sh's link logic, parametrized by repo dir)

```sh
# deploy.sh — symlink a content repo's manifest entries into $HOME. Sourced, never executed.
# Depends on common.sh (os_name).

# deploy_repo <repo_dir> [--dry-run]
deploy_repo() {
  _repo=$1; _dry=0
  [ "${2:-}" = "--dry-run" ] && _dry=1
  _os=$(os_name)
  _manifest="$_repo/manifest"
  [ -f "$_manifest" ] || { printf 'homedir-manager: no manifest in %s\n' "$_repo" >&2; return 1; }

  _ts=$(date +%Y%m%d-%H%M%S)
  _backup="$HOME/.dotfiles-backup/$_ts"
  _linked=0; _skipped=0; _backed=0; _missing=0

  set -f
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%%#*}
    # shellcheck disable=SC2086
    set -- $line
    [ "$#" -eq 0 ] && continue
    rel=$1; tag=${2:-}
    if [ -n "$tag" ] && [ "$tag" != "$_os" ]; then continue; fi

    src="$_repo/$rel"; dest="$HOME/$rel"
    if [ ! -e "$src" ] && [ ! -L "$src" ]; then
      printf 'MISSING  %s (not in %s)\n' "$rel" "$_repo"; _missing=$((_missing+1)); continue
    fi
    if [ -L "$dest" ] && [ "$dest" -ef "$src" ]; then _skipped=$((_skipped+1)); continue; fi
    if [ "$_dry" = 1 ]; then
      if [ -e "$dest" ] || [ -L "$dest" ]; then printf 'WOULD BACKUP+LINK  %s\n' "$rel"
      else printf 'WOULD LINK  %s\n' "$rel"; fi
      continue
    fi
    mkdir -p "$(dirname "$dest")"
    if [ -e "$dest" ] || [ -L "$dest" ]; then
      mkdir -p "$(dirname "$_backup/$rel")"; mv "$dest" "$_backup/$rel"
      _backed=$((_backed+1)); printf 'BACKUP   %s -> %s\n' "$rel" "$_backup/$rel"
    fi
    ln -s "$src" "$dest"; _linked=$((_linked+1)); printf 'LINK     %s\n' "$rel"
  done < "$_manifest"
  set +f

  printf 'linked=%s skipped=%s backed_up=%s missing=%s\n' "$_linked" "$_skipped" "$_backed" "$_missing"
}
```

- [ ] **Step 4: Run the test, expect pass**

Run: `sh ~/git/homedir-manager/test/test_deploy.sh`
Expected: `RESULT run=11 failed=0`.

- [ ] **Step 5: Commit**

```bash
cd ~/git/homedir-manager && git add -A
git commit -m "Port deploy engine to lib/deploy.sh (deploy_repo, repo-parametrized)"
```

---

### Task A4: Wire `install` verb to discovery + deploy (multi-repo)

**Files:**
- Modify: `~/git/homedir-manager/bin/homedir-manager` (the `install)` case)
- Test: `~/git/homedir-manager/test/test_install_cmd.sh`

- [ ] **Step 1: Write the failing test — install deploys every discovered repo**

```sh
#!/bin/sh
set -u
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
BIN=$(CDPATH= cd -- "$HERE/../bin" && pwd -P)
. "$HERE/assert.sh"

# Two managed repos + one unmanaged, under a fake base; install links both managed.
TMP=$(mktempd); mkdir -p "$TMP/base/r1" "$TMP/base/r2" "$TMP/base/nope" "$TMP/home"
: > "$TMP/base/r1/.homedir-manager.conf"; echo a > "$TMP/base/r1/one.conf"; printf 'one.conf\n' > "$TMP/base/r1/manifest"
: > "$TMP/base/r2/.homedir-manager.conf"; echo b > "$TMP/base/r2/two.conf"; printf 'two.conf\n' > "$TMP/base/r2/manifest"
echo c > "$TMP/base/nope/three.conf"; printf 'three.conf\n' > "$TMP/base/nope/manifest"  # no marker
UNAME_OVERRIDE=Darwin HOME="$TMP/home" HOMEDIR_MANAGER_BASE="$TMP/base" \
  "$BIN/homedir-manager" install >/dev/null
assert_symlink_to "$TMP/home/one.conf" "$TMP/base/r1/one.conf" "repo r1 deployed"
assert_symlink_to "$TMP/home/two.conf" "$TMP/base/r2/two.conf" "repo r2 deployed"
if [ -e "$TMP/home/three.conf" ]; then n=present; else n=absent; fi
assert_eq "absent" "$n" "unmarked repo not deployed"
rm -rf "$TMP"

printf 'RESULT run=%s failed=%s\n' "$TESTS_RUN" "$TESTS_FAILED"
```

- [ ] **Step 2: Run it, expect failure**

Run: `sh ~/git/homedir-manager/test/test_install_cmd.sh`
Expected: FAIL — `install` still calls `hm_die "not yet implemented"`.

- [ ] **Step 3: Implement the `install` verb**

In `bin/homedir-manager`, add the lib sources after the common.sh source:
```sh
. "$HM_LIB/config.sh"
. "$HM_LIB/deploy.sh"
. "$HM_LIB/audit.sh"
. "$HM_LIB/defaults.sh"
```
Replace the `install)` case with:
```sh
  install)
    _dry=''
    [ "${1:-}" = "--dry-run" ] && _dry='--dry-run'
    _any=0
    discover_repos | while IFS= read -r repo; do
      printf '== %s ==\n' "$repo"
      deploy_repo "$repo" $_dry
    done
    _any=$(discover_repos | wc -l | tr -d ' ')
    [ "$_any" = 0 ] && printf 'homedir-manager: no managed repos found under %s\n' "$(hm_base)" >&2
    ;;
```
(Note: `audit.sh` and `defaults.sh` are created in later tasks; create empty placeholder files now so the sources don't fail:
```bash
printf '# audit.sh\n'    > ~/git/homedir-manager/lib/audit.sh
printf '# defaults.sh\n' > ~/git/homedir-manager/lib/defaults.sh
```)

- [ ] **Step 4: Run the test, expect pass**

Run: `sh ~/git/homedir-manager/test/test_install_cmd.sh`
Expected: `RESULT run=3 failed=0`.

- [ ] **Step 5: Commit**

```bash
cd ~/git/homedir-manager && git add -A
git commit -m "Wire install verb to multi-repo discovery + deploy"
```

---

### Task A5: Audit engine (`lib/audit.sh`) — port + generalize dotfiles-audit

**Files:**
- Modify: `~/git/homedir-manager/lib/audit.sh`
- Test: `~/git/homedir-manager/test/test_audit.sh`

Port the three checks from `~/git/dotfiles/bin/dotfiles-audit`: (1) secret-pattern scan of tracked files, (2) deploy drift, (3) perms on secret-bearing files. Generalize: iterate discovered repos; the perms check reads `HM_SECRET_FILES` from each repo's sourced marker instead of the hardcoded `~/.config/op/env`. Keep the `os_perm` helper that tries Linux `stat -c` before macOS `stat -f`.

- [ ] **Step 1: Write the failing test**

```sh
#!/bin/sh
set -u
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
LIB=$(CDPATH= cd -- "$HERE/../lib" && pwd -P)
. "$HERE/assert.sh"
. "$LIB/common.sh"
. "$LIB/config.sh"
. "$LIB/audit.sh"

# os_perm returns octal perms on this platform
TMP=$(mktempd); : > "$TMP/f"; chmod 600 "$TMP/f"
assert_eq "600" "$(os_perm "$TMP/f")" "os_perm reads 600"
rm -rf "$TMP"

# secret scan flags a private key in a tracked file
TMP=$(mktempd); mkdir -p "$TMP/repo"; cd "$TMP/repo"
git init -q; : > "$HM_MARKER"
printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n' > leaked.txt
git add -A >/dev/null 2>&1
out=$(audit_secrets "$TMP/repo" 2>&1); rc=$?
echo "$out" | grep -q 'leaked.txt' && hit=yes || hit=no
assert_eq "yes" "$hit" "secret scan flags leaked private key"
assert_eq "1" "$rc" "audit_secrets returns 1 on finding"
cd "$HERE"; rm -rf "$TMP"

# perms check: HM_SECRET_FILES from marker, flags non-600
TMP=$(mktempd); mkdir -p "$TMP/repo"
secret="$TMP/secret.env"; : > "$secret"; chmod 644 "$secret"
printf 'HM_SECRET_FILES="%s"\n' "$secret" > "$TMP/repo/$HM_MARKER"
out=$(audit_perms "$TMP/repo" 2>&1); rc=$?
echo "$out" | grep -q "$secret" && hit=yes || hit=no
assert_eq "yes" "$hit" "perms check flags non-600 secret file"
assert_eq "1" "$rc" "audit_perms returns 1 when a file is mis-permed"
chmod 600 "$secret"
out=$(audit_perms "$TMP/repo" 2>&1); rc=$?
assert_eq "0" "$rc" "audit_perms returns 0 when 600"
rm -rf "$TMP"

printf 'RESULT run=%s failed=%s\n' "$TESTS_RUN" "$TESTS_FAILED"
```

- [ ] **Step 2: Run it, expect failure**

Run: `sh ~/git/homedir-manager/test/test_audit.sh`
Expected: FAIL — `audit.sh` is an empty placeholder.

- [ ] **Step 3: Implement `lib/audit.sh`**

```sh
# audit.sh — leak / drift / perms checks across managed repos. Sourced, never executed.
# Depends on common.sh (os_name) and config.sh (discover_repos, hm_base).

# Literal credential shapes that must never be committed.
HM_SECRET_PATTERNS='-----BEGIN [A-Z ]*PRIVATE KEY-----|ops_[A-Za-z0-9]{40,}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|sk-[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}'

# os_perm <file> — octal perms; Linux stat -c first, macOS stat -f fallback.
os_perm() { stat -c '%a' "$1" 2>/dev/null || stat -f '%A' "$1" 2>/dev/null; }

# audit_secrets <repo> — grep tracked files for credential shapes. Returns 1 on any hit.
audit_secrets() {
  repo=$1; name=$(basename "$repo")
  hits=$(git -C "$repo" grep -nIE "$HM_SECRET_PATTERNS" -- ':!docs/*' 2>/dev/null || true)
  bad=$(git -C "$repo" ls-files 2>/dev/null | grep -nE '(^|/)\.env|\.(pem|key|p12|pfx)$|credentials|\.crt$' || true)
  rc=0
  if [ -n "$hits" ]; then printf '[%s] possible secret(s) — investigate + ROTATE:\n%s\n' "$name" "$hits"; rc=1; fi
  if [ -n "$bad" ]; then printf '[%s] suspicious tracked filename(s): %s\n' "$name" "$(printf '%s' "$bad" | tr '\n' ' ')"; rc=1; fi
  return $rc
}

# audit_drift <repo> — every manifest entry for this OS is symlinked into $HOME. Returns 1 on drift.
audit_drift() {
  repo=$1; name=$(basename "$repo"); os=$(os_name); rc=0
  [ -f "$repo/manifest" ] || return 0
  set -f
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%%#*}; # shellcheck disable=SC2086
    set -- $line; [ "$#" -eq 0 ] && continue
    rel=$1; tag=${2:-}
    [ -n "$tag" ] && [ "$tag" != "$os" ] && continue
    src="$repo/$rel"; dest="$HOME/$rel"
    [ -e "$src" ] || { printf '[%s] manifest entry missing from repo: %s\n' "$name" "$rel"; rc=1; continue; }
    if [ -L "$dest" ] && [ "$dest" -ef "$src" ]; then :; else
      printf '[%s] not deployed (run install): %s\n' "$name" "$rel"; rc=1
    fi
  done < "$repo/manifest"
  set +f
  return $rc
}

# audit_perms <repo> — HM_SECRET_FILES (from the repo marker) must be 600. Returns 1 on violation.
audit_perms() {
  repo=$1; rc=0
  HM_SECRET_FILES=''
  # shellcheck disable=SC1090
  [ -f "$repo/$HM_MARKER" ] && . "$repo/$HM_MARKER"
  for f in $HM_SECRET_FILES; do
    [ -e "$f" ] || continue
    p=$(os_perm "$f")
    [ "$p" = "600" ] || { printf '%s is %s (want 600)\n' "$f" "$p"; rc=1; }
  done
  return $rc
}

# audit_all [base] — run all checks across discovered repos. Returns 1 if any finding.
audit_all() {
  base=${1:-$(hm_base)}; findings=0
  for repo in $(discover_repos "$base"); do
    audit_secrets "$repo" || findings=$((findings+1))
    audit_drift   "$repo" || findings=$((findings+1))
    audit_perms   "$repo" || findings=$((findings+1))
  done
  [ "$findings" -eq 0 ] && printf 'PASS — no findings\n' || printf 'FAIL — %s finding(s)\n' "$findings"
  [ "$findings" -eq 0 ]
}
```

- [ ] **Step 4: Run the test, expect pass**

Run: `sh ~/git/homedir-manager/test/test_audit.sh`
Expected: `RESULT run=6 failed=0`.

- [ ] **Step 5: Commit**

```bash
cd ~/git/homedir-manager && git add -A
git commit -m "Port audit engine to lib/audit.sh (per-repo, marker-driven perms)"
```

---

### Task A6: Wire `audit` verb

**Files:**
- Modify: `~/git/homedir-manager/bin/homedir-manager` (the `audit)` case)
- Test: `~/git/homedir-manager/test/test_audit_cmd.sh`

- [ ] **Step 1: Write the failing test**

```sh
#!/bin/sh
set -u
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
BIN=$(CDPATH= cd -- "$HERE/../bin" && pwd -P)
. "$HERE/assert.sh"

# Clean managed repo with everything deployed -> PASS, exit 0
TMP=$(mktempd); mkdir -p "$TMP/base/r" "$TMP/home"; cd "$TMP/base/r"
git init -q; : > .homedir-manager.conf; echo x > a.conf; printf 'a.conf\n' > manifest; git add -A >/dev/null 2>&1
ln -s "$TMP/base/r/a.conf" "$TMP/home/a.conf"
out=$(UNAME_OVERRIDE=Darwin HOME="$TMP/home" HOMEDIR_MANAGER_BASE="$TMP/base" "$BIN/homedir-manager" audit 2>&1); rc=$?
echo "$out" | grep -q 'PASS' && p=yes || p=no
assert_eq "yes" "$p" "clean repo audits PASS"
assert_eq "0" "$rc" "audit exits 0 when clean"
cd "$HERE"; rm -rf "$TMP"

printf 'RESULT run=%s failed=%s\n' "$TESTS_RUN" "$TESTS_FAILED"
```

- [ ] **Step 2: Run it, expect failure**

Run: `sh ~/git/homedir-manager/test/test_audit_cmd.sh`
Expected: FAIL — `audit` still stubbed.

- [ ] **Step 3: Implement the `audit` verb**

Replace the `audit)` case:
```sh
  audit) audit_all || exit 1 ;;
```

- [ ] **Step 4: Run the test, expect pass**

Run: `sh ~/git/homedir-manager/test/test_audit_cmd.sh`
Expected: `RESULT run=2 failed=0`.

- [ ] **Step 5: Commit**

```bash
cd ~/git/homedir-manager && git add -A
git commit -m "Wire audit verb to audit_all"
```

---

### Task A7: `defaults` verb delegation (`lib/defaults.sh`)

**Files:**
- Modify: `~/git/homedir-manager/lib/defaults.sh`
- Modify: `~/git/homedir-manager/bin/homedir-manager` (the `defaults)` case)
- Test: `~/git/homedir-manager/test/test_defaults.sh`

The Swift binary is vendored later (join point). This task implements only the *delegation*: locate the built binary at `macos/.build/release/macos-defaults`, error cleanly on Linux, and pass arguments through.

- [ ] **Step 1: Write the failing test**

```sh
#!/bin/sh
set -u
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
LIB=$(CDPATH= cd -- "$HERE/../lib" && pwd -P)
. "$HERE/assert.sh"
. "$LIB/common.sh"
. "$LIB/defaults.sh"

# On Linux, defaults_cmd refuses cleanly
out=$(UNAME_OVERRIDE=Linux defaults_cmd apply /tmp/x 2>&1); rc=$?
echo "$out" | grep -qi 'macOS only' && m=yes || m=no
assert_eq "yes" "$m" "defaults refuses on Linux"
assert_eq "2" "$rc" "defaults exits 2 on Linux"

# When the binary is missing on macOS, it errors with a build hint (not a crash)
out=$(UNAME_OVERRIDE=Darwin HM_DEFAULTS_BIN=/nonexistent/macos-defaults defaults_cmd apply /tmp/x 2>&1); rc=$?
echo "$out" | grep -qi 'not built' && b=yes || b=no
assert_eq "yes" "$b" "missing binary reports not-built"
assert_eq "3" "$rc" "missing binary exits 3"

printf 'RESULT run=%s failed=%s\n' "$TESTS_RUN" "$TESTS_FAILED"
```

- [ ] **Step 2: Run it, expect failure**

Run: `sh ~/git/homedir-manager/test/test_defaults.sh`
Expected: FAIL — `defaults_cmd` undefined.

- [ ] **Step 3: Implement `lib/defaults.sh`**

```sh
# defaults.sh — delegate the `defaults` verb to the vendored Swift macos-defaults binary.
# Depends on common.sh (os_name). Sourced, never executed.

# defaults_cmd <apply|drift|capture> [args...]
defaults_cmd() {
  [ "$(os_name)" = "macos" ] || { printf 'homedir-manager: defaults is macOS only\n' >&2; return 2; }
  _bin=${HM_DEFAULTS_BIN:-}
  if [ -z "$_bin" ]; then
    # default location: macos/.build/release/macos-defaults relative to lib/
    _bin=$(CDPATH= cd -- "$HM_LIB/../macos" 2>/dev/null && pwd -P)/.build/release/macos-defaults
  fi
  [ -x "$_bin" ] || { printf 'homedir-manager: macos-defaults not built (run bootstrap); expected %s\n' "$_bin" >&2; return 3; }
  "$_bin" "$@"
}
```

- [ ] **Step 4: Wire the verb**

Replace the `defaults)` case:
```sh
  defaults) defaults_cmd "$@" ;;
```

- [ ] **Step 5: Run the test, expect pass**

Run: `sh ~/git/homedir-manager/test/test_defaults.sh`
Expected: `RESULT run=4 failed=0`.

- [ ] **Step 6: Run the full suite**

Run: `sh ~/git/homedir-manager/test/run.sh`
Expected: `TOTAL run=… failed=0`.

- [ ] **Step 7: Commit**

```bash
cd ~/git/homedir-manager && git add -A
git commit -m "Add defaults verb delegation to vendored macos-defaults"
```

---

### Task A8: bootstrap, docs, skill, marker template, README

**Files:**
- Create: `~/git/homedir-manager/bootstrap`
- Create: `~/git/homedir-manager/share/AUDITING.md` (de-personalized copy of dotfiles' docs/AUDITING.md)
- Create: `~/git/homedir-manager/share/SECRETS.md` (de-personalized copy of dotfiles' docs/SECRETS.md)
- Create: `~/git/homedir-manager/share/homedir-manager.conf.example`
- Create: `~/git/homedir-manager/skills/managing-homedir/SKILL.md` (generalized from managing-dotfiles)
- Create: `~/git/homedir-manager/README.md`

- [ ] **Step 1: Write `bootstrap`**

```sh
#!/bin/sh
# bootstrap — first-run setup: put homedir-manager on PATH, build the macOS helper, optional install.
set -eu
# shellcheck disable=SC1007
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)

# 1. PATH: symlink the dispatcher into the first writable ~/.local/bin or /usr/local/bin.
for d in "$HOME/.local/bin" /usr/local/bin; do
  if mkdir -p "$d" 2>/dev/null && [ -w "$d" ]; then
    ln -sf "$ROOT/bin/homedir-manager" "$d/homedir-manager"
    ln -sf "$ROOT/bin/homedir-manager" "$d/hm"
    printf 'linked homedir-manager + hm into %s\n' "$d"
    break
  fi
done

# 2. macOS: build the Swift helper if the toolchain is present.
if [ "$(uname -s)" = "Darwin" ] && [ -d "$ROOT/macos" ] && command -v swift >/dev/null 2>&1; then
  printf 'building macos-defaults helper...\n'
  ( cd "$ROOT/macos" && swift build -c release )
fi

printf 'bootstrap complete. Run: homedir-manager install\n'
```

```bash
chmod +x ~/git/homedir-manager/bootstrap
```

- [ ] **Step 2: Write the marker template**

```sh
# .homedir-manager.conf — marks this repo as a homedir-manager content repo.
# Presence alone is enough. Optional settings:
#   HM_SECRET_FILES — space-separated local files that must be chmod 600 (audited).
# Example:
#   HM_SECRET_FILES="$HOME/.config/op/env"
```

- [ ] **Step 3: De-personalize and copy the docs + skill**

Copy `~/git/dotfiles/docs/AUDITING.md` → `share/AUDITING.md` and `~/git/dotfiles/docs/SECRETS.md` → `share/SECRETS.md`, then edit: replace `dotfiles-audit` with `homedir-manager audit`, references to "Jesse's fleet"/specific hostnames with generic phrasing, and the hardcoded `~/.config/op/env` with "the files listed in `HM_SECRET_FILES`". Copy `~/git/dotfiles/.claude/skills/managing-dotfiles/SKILL.md` → `skills/managing-homedir/SKILL.md`, rename `name:` to `managing-homedir`, and rewrite the update/onboarding/audit instructions to use `homedir-manager <verb>`, the marker, and convention-with-override discovery instead of `./install.sh`.

- [ ] **Step 4: Write `README.md`**

Document: what it is, prerequisites (POSIX `sh` everywhere; Swift toolchain on macOS for the `defaults` verb), quickstart (clone, `./bootstrap`, add a `.homedir-manager.conf` marker to your content repos, `homedir-manager install`), the verbs, the marker format, and discovery (convention `~/git`, override `$HOMEDIR_MANAGER_BASE`).

- [ ] **Step 5: Verify the suite still passes + dispatcher help/version**

Run: `sh ~/git/homedir-manager/test/run.sh && ~/git/homedir-manager/bin/homedir-manager version`
Expected: `TOTAL run=… failed=0` then `0.1.0`.

- [ ] **Step 6: Commit**

```bash
cd ~/git/homedir-manager && git add -A
git commit -m "Add bootstrap, de-personalized docs, managing-homedir skill, README"
```

---

## Phase B — Live migration & cutover (operational; controller-executed, NOT autonomous)

> These tasks mutate Jesse's live content repos and fleet. They are executed by the controller
> in the foreground with Jesse, not delegated to an autonomous subagent. The "test" for each is
> the parity check: same symlinks resolve, `homedir-manager audit` PASSES. Do them on the
> primary machine first; only after parity is green do anything destructive (the `git rm`) get
> pushed, and only then roll to the rest of the fleet.

### Task B1: Add markers to content repos

- [ ] Add `.homedir-manager.conf` to `~/git/dotfiles` (empty/comment-only is fine).
- [ ] Add `.homedir-manager.conf` to `~/git/dotfiles-private` with `HM_SECRET_FILES="$HOME/.config/op/env"`.
- [ ] Commit each (do **not** push yet).

### Task B2: Parity validation on the primary machine (before any deletion)

- [ ] `~/git/homedir-manager/bootstrap` (links `homedir-manager`+`hm` onto PATH; builds helper if `macos/` present — it is not yet, that's fine).
- [ ] `homedir-manager install --dry-run` → expect **every** entry reports already-linked (`skipped`), i.e. zero `WOULD LINK`/`WOULD BACKUP+LINK`, proving the engine reproduces the exact deployment the old `install.sh` made.
- [ ] `homedir-manager audit` → expect `PASS` (the perms check now reads the private repo's `HM_SECRET_FILES`).
- [ ] If either shows drift, STOP and reconcile before proceeding. Do not delete the old `install.sh`.

### Task B3: Remove moved machinery from dotfiles (only after B2 is green)

- [ ] In `~/git/dotfiles`: `git rm install.sh bin/dotfiles-audit docs/AUDITING.md docs/SECRETS.md`, `git rm -r test/`, `git rm -r .claude/skills/managing-dotfiles`.
- [ ] Edit `~/git/dotfiles/manifest`: remove the `bin/dotfiles-audit` and `.claude/skills/managing-dotfiles` lines (now engine-deployed). Leave all content lines.
- [ ] `homedir-manager install` → it will back up the now-stale `~/.claude/skills/managing-dotfiles` symlink and the `~/bin/dotfiles-audit` symlink is left dangling; remove those stale deployed symlinks by hand (`rm ~/.claude/skills/managing-dotfiles` if it points into the deleted path) and re-run `homedir-manager install` to deploy the engine's `managing-homedir` skill via bootstrap.
- [ ] `homedir-manager audit` → expect `PASS`.
- [ ] Commit dotfiles. Push `homedir-manager`, `dotfiles`, `dotfiles-private`.

### Task B4: Fleet rollout (paradise-park, magic-kingdom, flower-garden)

For each host:
- [ ] `git -C ~/git/dotfiles pull`; `git -C ~/git/dotfiles-private pull`.
- [ ] Clone `homedir-manager` into `~/git/homedir-manager`; run `./bootstrap`.
- [ ] `homedir-manager install` then `homedir-manager audit` → expect `PASS`.
- [ ] Remove any stale `~/bin/dotfiles-audit` / `managing-dotfiles` symlinks left from the old layout.

### Task B5: Vendor macos-defaults at the join point

- [ ] When the `macos-defaults` worker reports a green build, copy its package into `~/git/homedir-manager/macos/` (sources + `Package.swift` + tests; not `.build/`).
- [ ] `cd ~/git/homedir-manager/macos && swift build -c release && swift test` → green.
- [ ] `homedir-manager defaults --help` (via the delegation) → prints the helper's help.
- [ ] Commit; re-bootstrap the fleet so each Mac builds the helper.

---

## Self-Review notes

- **Spec coverage:** topology (B1–B5), engine layout (A1), verbs install/audit/defaults (A4/A6/A7), discovery (A2), migration incl. parity-before-deletion (B2→B3), testing harness (A1, per-task tests), distribution/bootstrap/docs (A8). macos-defaults itself is its own spec/plan (vendored in B5).
- **Marker format** deliberately changed from `.toml` to sh-sourceable `.homedir-manager.conf`; spec to be updated to match.
- **No new untested logic:** every lib function has a test task before its wiring.
