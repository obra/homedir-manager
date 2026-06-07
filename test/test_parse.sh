#!/bin/sh
set -u
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
LIB=$(CDPATH= cd -- "$HERE/../lib" && pwd -P)
. "$HERE/assert.sh"
. "$LIB/common.sh"

# chk <line> -> "<rel>|<tag>"
chk() { parse_manifest_line "$1"; printf '%s|%s' "$HM_REL" "$HM_TAG"; }

assert_eq "bin/idb|" "$(chk 'bin/idb')" "plain path, no tag"
assert_eq ".hammerspoon|macos" "$(chk '.hammerspoon        macos')" "path + macos tag (multi-space)"
assert_eq ".config/zsh/linux.zsh|linux" "$(chk '.config/zsh/linux.zsh  linux')" "path + linux tag"
assert_eq "Library/Application Support/Code/User/settings.json|macos" \
  "$(chk 'Library/Application Support/Code/User/settings.json   macos')" "spaced path + macos tag"
assert_eq "Library/Application Support/App/x.json|" \
  "$(chk 'Library/Application Support/App/x.json')" "spaced path, no tag"
assert_eq ".config/zsh/macos.zsh|macos" "$(chk '.config/zsh/macos.zsh  macos')" \
  "path component containing 'macos' preserved, trailing tag stripped"
assert_eq "bin/idb|" "$(chk 'bin/idb   # trailing comment')" "trailing comment stripped"

# blank / comment-only lines return non-zero so callers skip them
parse_manifest_line '# just a comment' && r=ok || r=skip; assert_eq "skip" "$r" "comment-only line skipped"
parse_manifest_line '    ' && r=ok || r=skip; assert_eq "skip" "$r" "blank line skipped"

printf 'RESULT run=%s failed=%s\n' "$TESTS_RUN" "$TESTS_FAILED"
