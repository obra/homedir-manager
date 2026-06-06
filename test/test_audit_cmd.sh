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
