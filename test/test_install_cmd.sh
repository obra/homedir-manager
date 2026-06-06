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
rc=0
UNAME_OVERRIDE=Darwin HOME="$TMP/home" HOMEDIR_MANAGER_BASE="$TMP/base" \
  "$BIN/homedir-manager" install >/dev/null || rc=$?
assert_eq "0" "$rc" "install exits 0 on success"
assert_symlink_to "$TMP/home/one.conf" "$TMP/base/r1/one.conf" "repo r1 deployed"
assert_symlink_to "$TMP/home/two.conf" "$TMP/base/r2/two.conf" "repo r2 deployed"
if [ -e "$TMP/home/three.conf" ]; then n=present; else n=absent; fi
assert_eq "absent" "$n" "unmarked repo not deployed"
rm -rf "$TMP"

printf 'RESULT run=%s failed=%s\n' "$TESTS_RUN" "$TESTS_FAILED"
