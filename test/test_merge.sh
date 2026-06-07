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
