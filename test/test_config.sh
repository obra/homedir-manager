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
