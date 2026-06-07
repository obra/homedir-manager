# merge-children Manifest Directive Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `merge-children` manifest directive to homedir-manager that symlinks each *child* of a repo directory into the target directory individually (auto-discovering new children, leaving unmanaged siblings alone), selected by an explicit leading keyword — never by a trailing slash.

**Architecture:** Three sourced POSIX-sh libs change. `lib/common.sh::parse_manifest_line` learns the leading `merge-children` keyword (sets `HM_MERGE`) and rejects any trailing-slash path as a hard error (the rsync footgun guard). `lib/deploy.sh` factors its per-entry link logic into a `_deploy_path` helper and, for a merge entry, applies it to each child. `lib/audit.sh::audit_drift` checks each merged child and surfaces dangling orphan symlinks (a child removed from the repo) that the repo→home-only drift check would otherwise miss.

**Tech Stack:** POSIX sh (`set -eu`), the repo's hand-rolled `test/assert.sh` harness (run via `sh test/run.sh`), shellcheck v0.11.0 (`shellcheck -x -s sh`).

**Context for the implementer:**
- Locals are `_`-prefixed; sh has no `local`, so vars are effectively global within a call — `_deploy_path` deliberately reads/writes `deploy_repo`'s accumulators (`_repo`, `_dry`, `_backup`, `_linked`, `_skipped`, `_backed`, `_missing`).
- Manifest grammar today: `<repo-relative-path> [macos|linux]`, `#` comments, paths may contain spaces. After this change a leading `merge-children ` keyword may precede that.
- Tests override behavior with `UNAME_OVERRIDE=Darwin` and `HOME="$TMP/home"`. Each test file ends by printing `RESULT run=<n> failed=<n>`.
- Run a single test file with `sh test/test_<name>.sh`; run all with `sh test/run.sh`.

---

## File Structure

- **Modify** `lib/common.sh` — `parse_manifest_line` gains `HM_MERGE` + trailing-slash guard; the SC2034 disable comment adds `HM_MERGE`.
- **Modify** `lib/deploy.sh` — extract `_deploy_path`; `deploy_repo` branches on `HM_MERGE`.
- **Modify** `lib/audit.sh` — `audit_drift` branches on `HM_MERGE`: per-child drift + orphan detection.
- **Create** `test/test_merge.sh` — parser keyword, trailing-slash error, deploy-merge, sibling-preservation, idempotency, dry-run, audit drift-on-child, audit orphan.
- **Modify** `README.md` — document the directive and the no-trailing-slash rule.

Existing `test/test_parse.sh`, `test/test_deploy.sh`, `test/test_audit.sh` must stay green throughout (the deploy refactor in Task 2 is behavior-preserving).

---

## Task 1: Parser — `merge-children` keyword + trailing-slash guard

**Files:**
- Modify: `lib/common.sh:2` (SC2034 disable comment), `lib/common.sh:23-35` (`parse_manifest_line`)
- Create: `test/test_merge.sh`

- [ ] **Step 1: Write the failing tests** — create `test/test_merge.sh`:

```sh
#!/bin/sh
set -u
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
LIB=$(CDPATH= cd -- "$HERE/../lib" && pwd -P)
. "$HERE/assert.sh"
. "$LIB/common.sh"
. "$LIB/deploy.sh"
. "$LIB/config.sh"
. "$LIB/audit.sh"

# --- Parser: merge-children keyword ---
# chk <line> -> "<rel>|<tag>|<merge>"
chk() { parse_manifest_line "$1"; printf '%s|%s|%s' "$HM_REL" "$HM_TAG" "${HM_MERGE:-}"; }

assert_eq ".codex/skills||1"      "$(chk 'merge-children .codex/skills')"        "merge keyword sets HM_MERGE, strips keyword"
assert_eq ".codex/skills|macos|1" "$(chk 'merge-children .codex/skills  macos')" "merge keyword + os tag"
assert_eq ".codex/skills||"       "$(chk '.codex/skills')"                        "no keyword => HM_MERGE empty"

# HM_MERGE must not leak from a previous merge line to a plain one
parse_manifest_line 'merge-children .codex/skills' >/dev/null
parse_manifest_line 'bin/idb' >/dev/null
assert_eq "" "${HM_MERGE:-}" "HM_MERGE reset on a non-merge line"

# --- Parser: trailing slash is a hard error (rsync footgun guard) ---
err=$( (parse_manifest_line 'sub/') 2>&1 ); rc=$?
assert_eq "1" "$rc" "trailing-slash path aborts non-zero"
echo "$err" | grep -q 'trailing slash' && g=yes || g=no
assert_eq "yes" "$g" "trailing-slash error message mentions trailing slash"

# even on a merge entry, a trailing slash is an error (keyword selects, never punctuation)
rc2=$( (parse_manifest_line 'merge-children .codex/skills/') >/dev/null 2>&1; echo $? )
assert_eq "1" "$rc2" "merge entry with trailing slash also aborts"

printf 'RESULT run=%s failed=%s\n' "$TESTS_RUN" "$TESTS_FAILED"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `sh test/test_merge.sh`
Expected: FAILs — `HM_MERGE` is unset so the first asserts mismatch (`...||` vs `...|1`), and `parse_manifest_line 'sub/'` returns 0 instead of aborting.

- [ ] **Step 3: Implement the parser change** — replace `lib/common.sh:23-35` (`parse_manifest_line`) with:

```sh
parse_manifest_line() {
  HM_MERGE=''
  _l=${1%%#*}
  _l=${_l%"${_l##*[![:space:]]}"}              # rtrim
  [ -z "$_l" ] && { HM_REL=''; HM_TAG=''; return 1; }
  # Explicit merge directive: a leading `merge-children` keyword. Mode is NEVER selected by
  # punctuation (see the trailing-slash guard below) — that is the rsync `src/` vs `src` footgun.
  case "$_l" in
    merge-children[[:space:]]*)
      HM_MERGE=1
      _l=${_l#merge-children}
      _l=${_l#"${_l%%[![:space:]]*}"}          # ltrim the whitespace after the keyword
      ;;
  esac
  case "$_l" in
    *[[:space:]]macos) HM_TAG=macos; _l=${_l%macos} ;;
    *[[:space:]]linux) HM_TAG=linux; _l=${_l%linux} ;;
    *)                 HM_TAG='' ;;
  esac
  HM_REL=${_l%"${_l##*[![:space:]]}"}          # rtrim whitespace left before the stripped tag
  [ -z "$HM_REL" ] && return 1
  case "$HM_REL" in
    */) hm_die "trailing slash on '$HM_REL'; to merge a directory's children use the 'merge-children' directive" ;;
  esac
  return 0
}
```

- [ ] **Step 4: Update the SC2034 disable comment** — change `lib/common.sh:2` from:

```sh
# shellcheck disable=SC2034  # HM_MARKER/HM_REL/HM_TAG are consumed by the scripts that source this.
```

to:

```sh
# shellcheck disable=SC2034  # HM_MARKER/HM_REL/HM_TAG/HM_MERGE are consumed by the scripts that source this.
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `sh test/test_merge.sh`
Expected: PASS for every parser assert; `RESULT run=7 failed=0` (the deploy/audit asserts come in later tasks but are not in the file yet).

- [ ] **Step 6: Confirm the existing parser tests still pass**

Run: `sh test/test_parse.sh`
Expected: ends with `failed=0`; every existing parser assert still passes (no existing line uses the keyword or a trailing slash).

- [ ] **Step 7: shellcheck**

Run: `shellcheck -x -s sh lib/common.sh`
Expected: no output (clean).

- [ ] **Step 8: Commit**

```sh
git add lib/common.sh test/test_merge.sh
git commit -m "feat(parser): merge-children keyword + trailing-slash guard"
```

---

## Task 2: Deploy — extract `_deploy_path`, expand merge entries

**Files:**
- Modify: `lib/deploy.sh:1-41` (extract helper; branch `deploy_repo` on `HM_MERGE`)
- Test: `test/test_merge.sh` (append), `test/test_deploy.sh` (must stay green)

- [ ] **Step 1: Write the failing tests** — append to `test/test_merge.sh` *before* its final `RESULT` line:

```sh
# --- Deploy: merge-children symlinks each child, leaves unmanaged siblings alone ---
TMP=$(mktempd); mkdir -p "$TMP/repo/.codex/skills/alpha" "$TMP/repo/.codex/skills/beta" "$TMP/home/.codex/skills"
echo a > "$TMP/repo/.codex/skills/alpha/SKILL.md"; echo b > "$TMP/repo/.codex/skills/beta/SKILL.md"
ln -s /somewhere/external "$TMP/home/.codex/skills/external"   # unmanaged sibling
printf 'merge-children .codex/skills\n' > "$TMP/repo/manifest"
UNAME_OVERRIDE=Darwin HOME="$TMP/home" deploy_repo "$TMP/repo" >/dev/null
assert_symlink_to "$TMP/home/.codex/skills/alpha" "$TMP/repo/.codex/skills/alpha" "merge child alpha linked"
assert_symlink_to "$TMP/home/.codex/skills/beta"  "$TMP/repo/.codex/skills/beta"  "merge child beta linked"
assert_symlink_to "$TMP/home/.codex/skills/external" "/somewhere/external" "unmanaged sibling untouched"
if [ -d "$TMP/home/.codex/skills" ] && [ ! -L "$TMP/home/.codex/skills" ]; then pp=real; else pp=notreal; fi
assert_eq "real" "$pp" "merge target dir stays a real directory"
rm -rf "$TMP"

# --- Deploy: merge is idempotent and dry-run mutates nothing ---
TMP=$(mktempd); mkdir -p "$TMP/repo/.codex/skills/alpha" "$TMP/home"
echo a > "$TMP/repo/.codex/skills/alpha/SKILL.md"
printf 'merge-children .codex/skills\n' > "$TMP/repo/manifest"
UNAME_OVERRIDE=Darwin HOME="$TMP/home" deploy_repo "$TMP/repo" >/dev/null
out=$(UNAME_OVERRIDE=Darwin HOME="$TMP/home" deploy_repo "$TMP/repo")
echo "$out" | grep -q 'linked=0' && im=yes || im=no
assert_eq "yes" "$im" "second merge run is idempotent (linked=0)"
rm -rf "$TMP"

TMP=$(mktempd); mkdir -p "$TMP/repo/.codex/skills/alpha" "$TMP/home"
echo a > "$TMP/repo/.codex/skills/alpha/SKILL.md"
printf 'merge-children .codex/skills\n' > "$TMP/repo/manifest"
UNAME_OVERRIDE=Darwin HOME="$TMP/home" deploy_repo "$TMP/repo" --dry-run >/dev/null
if [ ! -e "$TMP/home/.codex/skills/alpha" ] && [ ! -L "$TMP/home/.codex/skills/alpha" ]; then dz=absent; else dz=present; fi
assert_eq "absent" "$dz" "dry-run creates no merge children"
rm -rf "$TMP"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `sh test/test_merge.sh`
Expected: the new deploy asserts FAIL — `deploy_repo` ignores `HM_MERGE` today, so it symlinks the directory `.codex/skills` itself instead of merging children, and `$TMP/home/.codex/skills/alpha` is not a symlink to the repo child.

- [ ] **Step 3: Implement the deploy change** — replace the entire body of `lib/deploy.sh` with (extracts `_deploy_path`, branches on `HM_MERGE`):

```sh
# deploy.sh — symlink a content repo's manifest entries into $HOME. Sourced, never executed.
# Depends on common.sh (os_name, parse_manifest_line).

# _deploy_path <rel> — symlink $HOME/<rel> -> $_repo/<rel>, clobber-safe. Reads $_repo/$_dry/
# $_backup and bumps deploy_repo's accumulators ($_linked/$_skipped/$_backed/$_missing).
_deploy_path() {
  _r=$1; _s="$_repo/$_r"; _d="$HOME/$_r"
  if [ ! -e "$_s" ] && [ ! -L "$_s" ]; then
    printf 'MISSING  %s (not in %s)\n' "$_r" "$_repo"; _missing=$((_missing+1)); return
  fi
  # shellcheck disable=SC3013  # -ef is a universal extension (bash 3.2, dash, busybox, ksh)
  if [ -L "$_d" ] && [ "$_d" -ef "$_s" ]; then _skipped=$((_skipped+1)); return; fi
  if [ "$_dry" = 1 ]; then
    if [ -e "$_d" ] || [ -L "$_d" ]; then printf 'WOULD BACKUP+LINK  %s\n' "$_r"
    else printf 'WOULD LINK  %s\n' "$_r"; fi
    return
  fi
  mkdir -p "$(dirname "$_d")"
  if [ -e "$_d" ] || [ -L "$_d" ]; then
    mkdir -p "$(dirname "$_backup/$_r")"; mv "$_d" "$_backup/$_r"
    _backed=$((_backed+1)); printf 'BACKUP   %s -> %s\n' "$_r" "$_backup/$_r"
  fi
  ln -s "$_s" "$_d"; _linked=$((_linked+1)); printf 'LINK     %s\n' "$_r"
}

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

  while IFS= read -r _line || [ -n "$_line" ]; do
    parse_manifest_line "$_line" || continue
    _rel=$HM_REL; _tag=$HM_TAG
    if [ -n "$_tag" ] && [ "$_tag" != "$_os" ]; then continue; fi

    if [ "${HM_MERGE:-}" = 1 ]; then
      _mdir="$_repo/$_rel"
      if [ ! -d "$_mdir" ]; then
        printf 'MISSING  %s (merge dir not in %s)\n' "$_rel" "$_repo"; _missing=$((_missing+1)); continue
      fi
      [ "$_dry" = 1 ] || mkdir -p "$HOME/$_rel"
      for _child in "$_mdir"/*; do
        [ -e "$_child" ] || [ -L "$_child" ] || continue   # empty-glob guard
        _deploy_path "$_rel/$(basename "$_child")"
      done
    else
      _deploy_path "$_rel"
    fi
  done < "$_manifest"

  printf 'linked=%s skipped=%s backed_up=%s missing=%s\n' "$_linked" "$_skipped" "$_backed" "$_missing"
}
```

- [ ] **Step 4: Run the new tests to verify they pass**

Run: `sh test/test_merge.sh`
Expected: all asserts PASS.

- [ ] **Step 5: Run the existing deploy tests (refactor must be behavior-preserving)**

Run: `sh test/test_deploy.sh`
Expected: `RESULT run=<n> failed=0` (unchanged from before the refactor).

- [ ] **Step 6: shellcheck**

Run: `shellcheck -x -s sh lib/deploy.sh`
Expected: no output (clean).

- [ ] **Step 7: Commit**

```sh
git add lib/deploy.sh test/test_merge.sh
git commit -m "feat(deploy): merge-children expands a dir's children into the target"
```

---

## Task 3: Audit — merge-aware drift + orphan detection

**Files:**
- Modify: `lib/audit.sh:21-37` (`audit_drift`)
- Test: `test/test_merge.sh` (append), `test/test_audit.sh` (must stay green)

- [ ] **Step 1: Write the failing tests** — append to `test/test_merge.sh` *before* its final `RESULT` line:

```sh
# --- Audit: a deployed merge dir is clean; an undeployed child is drift ---
TMP=$(mktempd); mkdir -p "$TMP/repo/.codex/skills/alpha" "$TMP/home"
: > "$TMP/repo/$HM_MARKER"
echo a > "$TMP/repo/.codex/skills/alpha/SKILL.md"
printf 'merge-children .codex/skills\n' > "$TMP/repo/manifest"
UNAME_OVERRIDE=Darwin HOME="$TMP/home" deploy_repo "$TMP/repo" >/dev/null
UNAME_OVERRIDE=Darwin HOME="$TMP/home" audit_drift "$TMP/repo" >/dev/null 2>&1 && d1=clean || d1=drift
assert_eq "clean" "$d1" "merge dir fully deployed => no drift"

rm "$TMP/home/.codex/skills/alpha"   # undeploy one child
out=$(UNAME_OVERRIDE=Darwin HOME="$TMP/home" audit_drift "$TMP/repo" 2>&1) && d2=clean || d2=drift
assert_eq "drift" "$d2" "undeployed merge child => drift"
echo "$out" | grep -q 'not deployed' && nd=yes || nd=no
assert_eq "yes" "$nd" "drift names the undeployed child"
rm -rf "$TMP"

# --- Audit: a child removed from the repo leaves a dangling orphan symlink that audit surfaces ---
TMP=$(mktempd); mkdir -p "$TMP/repo/.codex/skills/alpha" "$TMP/home"
: > "$TMP/repo/$HM_MARKER"
echo a > "$TMP/repo/.codex/skills/alpha/SKILL.md"
printf 'merge-children .codex/skills\n' > "$TMP/repo/manifest"
UNAME_OVERRIDE=Darwin HOME="$TMP/home" deploy_repo "$TMP/repo" >/dev/null
rm -rf "$TMP/repo/.codex/skills/alpha"   # remove from repo; ~ symlink now dangles
out=$(UNAME_OVERRIDE=Darwin HOME="$TMP/home" audit_drift "$TMP/repo" 2>&1) && o1=clean || o1=drift
assert_eq "drift" "$o1" "orphaned merge child => drift"
echo "$out" | grep -q 'orphan' && og=yes || og=no
assert_eq "yes" "$og" "orphan finding is reported"
rm -rf "$TMP"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `sh test/test_merge.sh`
Expected: the audit asserts FAIL — current `audit_drift` treats the merge entry as a single path `.codex/skills`, finds `$HOME/.codex/skills` is a real dir (not a symlink to the repo) and reports the wrong thing; it never inspects children or orphans.

- [ ] **Step 3: Implement the audit change** — replace `lib/audit.sh:21-37` (`audit_drift`) with:

```sh
# audit_drift <repo> — every manifest entry for this OS is symlinked into $HOME. Returns 1 on drift.
# For a merge-children entry, each child must be linked AND no dangling orphan (a symlink in the
# target dir pointing into the repo dir whose target was removed) may remain.
audit_drift() {
  _repo=$1; _name=$(basename "$_repo"); _os=$(os_name); _rc=0
  [ -f "$_repo/manifest" ] || return 0
  while IFS= read -r _line || [ -n "$_line" ]; do
    parse_manifest_line "$_line" || continue
    _rel=$HM_REL; _tag=$HM_TAG
    [ -n "$_tag" ] && [ "$_tag" != "$_os" ] && continue

    if [ "${HM_MERGE:-}" = 1 ]; then
      _mdir="$_repo/$_rel"
      [ -d "$_mdir" ] || { printf '[%s] merge dir missing from repo: %s\n' "$_name" "$_rel"; _rc=1; continue; }
      for _child in "$_mdir"/*; do
        [ -e "$_child" ] || [ -L "$_child" ] || continue
        _cr="$_rel/$(basename "$_child")"; _cs="$_repo/$_cr"; _cd="$HOME/$_cr"
        # shellcheck disable=SC3013  # -ef is a universal extension
        if [ -L "$_cd" ] && [ "$_cd" -ef "$_cs" ]; then :; else
          printf '[%s] not deployed (run install): %s\n' "$_name" "$_cr"; _rc=1
        fi
      done
      if [ -d "$HOME/$_rel" ]; then
        for _link in "$HOME/$_rel"/*; do
          [ -L "$_link" ] || continue
          case "$(readlink "$_link")" in
            "$_mdir"/*) [ -e "$_link" ] || { printf '[%s] orphaned symlink (repo child removed): %s\n' "$_name" "${_link#"$HOME/"}"; _rc=1; } ;;
          esac
        done
      fi
      continue
    fi

    _src="$_repo/$_rel"; _dest="$HOME/$_rel"
    [ -e "$_src" ] || { printf '[%s] manifest entry missing from repo: %s\n' "$_name" "$_rel"; _rc=1; continue; }
    # shellcheck disable=SC3013  # -ef is a universal extension (bash 3.2, dash, busybox, ksh)
    if [ -L "$_dest" ] && [ "$_dest" -ef "$_src" ]; then :; else
      printf '[%s] not deployed (run install): %s\n' "$_name" "$_rel"; _rc=1
    fi
  done < "$_repo/manifest"
  return $_rc
}
```

- [ ] **Step 4: Run the new tests to verify they pass**

Run: `sh test/test_merge.sh`
Expected: all asserts PASS.

- [ ] **Step 5: Run the existing audit tests**

Run: `sh test/test_audit.sh`
Expected: `RESULT run=<n> failed=0` (unchanged — no existing fixture uses a merge entry).

- [ ] **Step 6: shellcheck**

Run: `shellcheck -x -s sh lib/audit.sh`
Expected: no output (clean).

- [ ] **Step 7: Commit**

```sh
git add lib/audit.sh test/test_merge.sh
git commit -m "feat(audit): merge-children drift check + orphan detection"
```

---

## Task 4: Document the directive

**Files:**
- Modify: `README.md` (manifest-format section)

- [ ] **Step 1: Find where the manifest format is described**

Run: `grep -n -i 'manifest' README.md`
Expected: a section or line describing manifest entries (path + `macos`/`linux` tag). Note its location.

- [ ] **Step 2: Add the directive documentation** — under the manifest-format description in `README.md`, add this block (match the surrounding heading style; if there is no manifest section, add one titled `## Manifest format` near the install docs):

```markdown
A manifest entry is a repo-relative path, optionally followed by a `macos` or `linux` tag.
Lines beginning with `#` are comments.

To track a directory by symlinking **each of its children** individually — so new children
are picked up automatically and unmanaged siblings (host-local files, externally-managed
symlinks) are left alone — prefix the entry with the `merge-children` keyword:

    merge-children  .codex/skills
    merge-children  .codex/skills  macos

The directive is selected by the keyword, **never** by a trailing slash. A path that ends
in `/` is a hard error — this avoids the rsync `src/` vs `src` footgun where one invisible
character flips the behavior. Without the keyword, a directory entry symlinks the directory
itself.
```

- [ ] **Step 3: Commit**

```sh
git add README.md
git commit -m "docs: document the merge-children manifest directive"
```

---

## Task 5: Full suite + shellcheck gate

**Files:** none (verification only)

- [ ] **Step 1: Run the entire test suite**

Run: `sh test/run.sh`
Expected: final line `TOTAL run=<n> failed=0`. The new `test_merge.sh` block contributes its asserts; every existing file is unchanged-green.

- [ ] **Step 2: shellcheck the whole engine (matches CI)**

Run: `shellcheck -x -s sh bin/homedir-manager lib/*.sh bootstrap`
Expected: no output (clean) — same invocation as `.github/workflows/ci.yml`.

- [ ] **Step 3: Smoke-test end to end with a throwaway repo**

```sh
T=$(mktemp -d); mkdir -p "$T/base/r/.codex/skills/demo" "$T/home"
: > "$T/base/r/.homedir-manager.conf"
echo hi > "$T/base/r/.codex/skills/demo/SKILL.md"
printf 'merge-children .codex/skills\n' > "$T/base/r/manifest"
HOMEDIR_MANAGER_BASE="$T/base" HOME="$T/home" bin/homedir-manager install
ls -l "$T/home/.codex/skills/"
```
Expected: `install` prints `LINK .codex/skills/demo`; the `ls` shows `demo -> …/r/.codex/skills/demo`.

- [ ] **Step 4: Final commit if anything changed**

(No code expected here; if the smoke test surfaced a fix, commit it with a descriptive message.)

---

## Notes for follow-on work (NOT part of this plan)

- Switching the existing per-line `.claude/skills` block to a single `merge-children` entry is possible but deferred (spec §6).
- The content repos' manifests (`dotfiles`, `dotfiles-private`) will *use* `merge-children .codex/skills` as part of the separate config-sweep work — not here. This plan ships and tests the engine primitive only.
