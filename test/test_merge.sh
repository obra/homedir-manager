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

printf 'RESULT run=%s failed=%s\n' "$TESTS_RUN" "$TESTS_FAILED"
