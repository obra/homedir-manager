#!/bin/sh
set -u
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
BIN=$(CDPATH= cd -- "$HERE/../bin" && pwd -P)
. "$HERE/assert.sh"

# Regression: a multi-repo `install --dry-run` must NOT modify the filesystem for ANY repo.
# (Bug: the install verb's `_dry` was clobbered by deploy_repo's internal `_dry`, so every
# repo after the first deployed for real during a dry-run.)
TMP=$(mktempd); mkdir -p "$TMP/base/r1" "$TMP/base/r2" "$TMP/home"
: > "$TMP/base/r1/.homedir-manager.conf"; echo a > "$TMP/base/r1/one.conf"; printf 'one.conf\n' > "$TMP/base/r1/manifest"
: > "$TMP/base/r2/.homedir-manager.conf"; echo b > "$TMP/base/r2/two.conf"; printf 'two.conf\n' > "$TMP/base/r2/manifest"
out=$(UNAME_OVERRIDE=Darwin HOME="$TMP/home" HOMEDIR_MANAGER_BASE="$TMP/base" "$BIN/homedir-manager" install --dry-run)

if [ -e "$TMP/home/one.conf" ] || [ -L "$TMP/home/one.conf" ]; then a=present; else a=absent; fi
if [ -e "$TMP/home/two.conf" ] || [ -L "$TMP/home/two.conf" ]; then b=present; else b=absent; fi
assert_eq "absent" "$a" "dry-run does not deploy repo 1"
assert_eq "absent" "$b" "dry-run does not deploy repo 2 (the _dry-collision regression)"
if [ -d "$TMP/home/.dotfiles-backup" ]; then bk=exists; else bk=absent; fi
assert_eq "absent" "$bk" "dry-run creates no backup"
echo "$out" | grep -q 'WOULD LINK  one.conf' && w1=yes || w1=no
echo "$out" | grep -q 'WOULD LINK  two.conf' && w2=yes || w2=no
assert_eq "yes" "$w1" "repo 1 reported WOULD LINK (dry-run, not deployed)"
assert_eq "yes" "$w2" "repo 2 reported WOULD LINK (dry-run, not deployed)"
rm -rf "$TMP"

printf 'RESULT run=%s failed=%s\n' "$TESTS_RUN" "$TESTS_FAILED"
