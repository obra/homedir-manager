#!/bin/sh
set -u
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
LIB=$(CDPATH= cd -- "$HERE/../lib" && pwd -P)
. "$HERE/assert.sh"
. "$LIB/common.sh"
. "$LIB/config.sh"
. "$LIB/hooks.sh"

# Two managed repos (with .git) + an explicit hook source -> hook symlinked into each.
TMP=$(mktempd); mkdir -p "$TMP/base/r1/.git/hooks" "$TMP/base/r2/.git/hooks"
: > "$TMP/base/r1/$HM_MARKER"; : > "$TMP/base/r2/$HM_MARKER"
HOOK="$TMP/pre-push-src"; printf '#!/bin/sh\nexit 0\n' > "$HOOK"
install_hooks "$TMP/base" "$HOOK" >/dev/null
assert_symlink_to "$TMP/base/r1/.git/hooks/pre-push" "$HOOK" "hook installed in r1"
assert_symlink_to "$TMP/base/r2/.git/hooks/pre-push" "$HOOK" "hook installed in r2"

# idempotent — second run leaves the symlink in place
install_hooks "$TMP/base" "$HOOK" >/dev/null
assert_symlink_to "$TMP/base/r1/.git/hooks/pre-push" "$HOOK" "hook still linked after re-run"

# never clobber a pre-existing, hand-written (non-symlink) hook
printf '#!/bin/sh\necho mine\n' > "$TMP/base/r2/.git/hooks/pre-push.tmp"
rm "$TMP/base/r2/.git/hooks/pre-push"
mv "$TMP/base/r2/.git/hooks/pre-push.tmp" "$TMP/base/r2/.git/hooks/pre-push"
install_hooks "$TMP/base" "$HOOK" >/dev/null 2>&1
grep -q 'mine' "$TMP/base/r2/.git/hooks/pre-push" && k=preserved || k=clobbered
assert_eq "preserved" "$k" "existing non-symlink hook left untouched"
rm -rf "$TMP"

printf 'RESULT run=%s failed=%s\n' "$TESTS_RUN" "$TESTS_FAILED"
