#!/bin/sh
set -u
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
LIB=$(CDPATH= cd -- "$HERE/../lib" && pwd -P)
. "$HERE/assert.sh"
. "$LIB/common.sh"
. "$LIB/deploy.sh"

# OS-tag filtering via deploy_repo --dry-run
TMP=$(mktempd); mkdir -p "$TMP/repo" "$TMP/home"
: > "$TMP/repo/common.conf"; : > "$TMP/repo/maconly.conf"; : > "$TMP/repo/linonly.conf"
cat > "$TMP/repo/manifest" <<'EOF'
# a comment
common.conf
maconly.conf   macos
linonly.conf   linux
EOF
out=$(UNAME_OVERRIDE=Darwin HOME="$TMP/home" deploy_repo "$TMP/repo" --dry-run)
echo "$out" | grep -q 'common.conf'  && c=yes || c=no
echo "$out" | grep -q 'maconly.conf' && m=yes || m=no
echo "$out" | grep -q 'linonly.conf' && l=yes || l=no
assert_eq "yes" "$c" "common.conf included on macOS"
assert_eq "yes" "$m" "maconly.conf included on macOS"
assert_eq "no"  "$l" "linonly.conf excluded on macOS"
rm -rf "$TMP"

# dry-run makes no changes
TMP=$(mktempd); mkdir -p "$TMP/repo" "$TMP/home"; : > "$TMP/repo/common.conf"
printf 'common.conf\n' > "$TMP/repo/manifest"
UNAME_OVERRIDE=Darwin HOME="$TMP/home" deploy_repo "$TMP/repo" --dry-run >/dev/null
if [ ! -e "$TMP/home/common.conf" ] && [ ! -L "$TMP/home/common.conf" ]; then z=absent; else z=present; fi
assert_eq "absent" "$z" "dry-run creates nothing"
rm -rf "$TMP"

# real link, real parent dir
TMP=$(mktempd); mkdir -p "$TMP/repo/sub" "$TMP/home"; echo hi > "$TMP/repo/sub/n.conf"
printf 'sub/n.conf\n' > "$TMP/repo/manifest"
UNAME_OVERRIDE=Darwin HOME="$TMP/home" deploy_repo "$TMP/repo" >/dev/null
assert_symlink_to "$TMP/home/sub/n.conf" "$TMP/repo/sub/n.conf" "nested file linked"
if [ -d "$TMP/home/sub" ] && [ ! -L "$TMP/home/sub" ]; then p=real; else p=notreal; fi
assert_eq "real" "$p" "parent dir is real"
rm -rf "$TMP"

# idempotency: second run links nothing, no backup dir
TMP=$(mktempd); mkdir -p "$TMP/repo" "$TMP/home"; echo x > "$TMP/repo/a.conf"
printf 'a.conf\n' > "$TMP/repo/manifest"
UNAME_OVERRIDE=Darwin HOME="$TMP/home" deploy_repo "$TMP/repo" >/dev/null
out2=$(UNAME_OVERRIDE=Darwin HOME="$TMP/home" deploy_repo "$TMP/repo")
echo "$out2" | grep -q 'linked=0' && zz=yes || zz=no
assert_eq "yes" "$zz" "second run idempotent"
if [ -d "$TMP/home/.dotfiles-backup" ]; then b=exists; else b=absent; fi
assert_eq "absent" "$b" "no backup on idempotent re-run"
rm -rf "$TMP"

# broken symlink replaced
TMP=$(mktempd); mkdir -p "$TMP/repo" "$TMP/home"; echo r > "$TMP/repo/x.conf"
printf 'x.conf\n' > "$TMP/repo/manifest"
ln -s "$TMP/home/missing" "$TMP/home/x.conf"
UNAME_OVERRIDE=Darwin HOME="$TMP/home" deploy_repo "$TMP/repo" >/dev/null
assert_symlink_to "$TMP/home/x.conf" "$TMP/repo/x.conf" "broken link replaced"
rm -rf "$TMP"

# conflict: real file backed up, content preserved
TMP=$(mktempd); mkdir -p "$TMP/repo" "$TMP/home"; echo from-repo > "$TMP/repo/c.conf"
echo pre-existing > "$TMP/home/c.conf"
printf 'c.conf\n' > "$TMP/repo/manifest"
UNAME_OVERRIDE=Darwin HOME="$TMP/home" deploy_repo "$TMP/repo" >/dev/null
assert_symlink_to "$TMP/home/c.conf" "$TMP/repo/c.conf" "conflict replaced by symlink"
found=$(find "$TMP/home/.dotfiles-backup" -name c.conf -exec cat {} \; 2>/dev/null)
assert_eq "pre-existing" "$found" "original content preserved in backup"
rm -rf "$TMP"

# spaced path (e.g. ~/Library/Application Support/...) deploys correctly, OS tag still honored
TMP=$(mktempd); mkdir -p "$TMP/repo/Library/Application Support/App/User" "$TMP/home"
echo cfg > "$TMP/repo/Library/Application Support/App/User/settings.json"
printf 'Library/Application Support/App/User/settings.json   macos\n' > "$TMP/repo/manifest"
UNAME_OVERRIDE=Darwin HOME="$TMP/home" deploy_repo "$TMP/repo" >/dev/null
assert_symlink_to "$TMP/home/Library/Application Support/App/User/settings.json" \
  "$TMP/repo/Library/Application Support/App/User/settings.json" "spaced path deployed"
# and the macos-tagged spaced path is skipped on Linux
rm -rf "$TMP/home"; mkdir -p "$TMP/home"
UNAME_OVERRIDE=Linux HOME="$TMP/home" deploy_repo "$TMP/repo" >/dev/null
if [ -e "$TMP/home/Library/Application Support/App/User/settings.json" ]; then sp=present; else sp=absent; fi
assert_eq "absent" "$sp" "spaced macos-tagged path skipped on Linux"
rm -rf "$TMP"

printf 'RESULT run=%s failed=%s\n' "$TESTS_RUN" "$TESTS_FAILED"
