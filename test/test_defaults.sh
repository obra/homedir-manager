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
