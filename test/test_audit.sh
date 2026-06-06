#!/bin/sh
set -u
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
LIB=$(CDPATH= cd -- "$HERE/../lib" && pwd -P)
. "$HERE/assert.sh"
. "$LIB/common.sh"
. "$LIB/config.sh"
. "$LIB/audit.sh"

# os_perm returns octal perms on this platform
TMP=$(mktempd); : > "$TMP/f"; chmod 600 "$TMP/f"
assert_eq "600" "$(os_perm "$TMP/f")" "os_perm reads 600"
rm -rf "$TMP"

# secret scan flags a private key in a tracked file
TMP=$(mktempd); mkdir -p "$TMP/repo"; cd "$TMP/repo"
git init -q; : > "$HM_MARKER"
printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n' > leaked.txt
git add -A >/dev/null 2>&1
out=$(audit_secrets "$TMP/repo" 2>&1); rc=$?
echo "$out" | grep -q 'leaked.txt' && hit=yes || hit=no
assert_eq "yes" "$hit" "secret scan flags leaked private key"
assert_eq "1" "$rc" "audit_secrets returns 1 on finding"
cd "$HERE"; rm -rf "$TMP"

# perms check: HM_SECRET_FILES from marker, flags non-600
TMP=$(mktempd); mkdir -p "$TMP/repo"
secret="$TMP/secret.env"; : > "$secret"; chmod 644 "$secret"
printf 'HM_SECRET_FILES="%s"\n' "$secret" > "$TMP/repo/$HM_MARKER"
out=$(audit_perms "$TMP/repo" 2>&1); rc=$?
echo "$out" | grep -q "$secret" && hit=yes || hit=no
assert_eq "yes" "$hit" "perms check flags non-600 secret file"
assert_eq "1" "$rc" "audit_perms returns 1 when a file is mis-permed"
chmod 600 "$secret"
out=$(audit_perms "$TMP/repo" 2>&1); rc=$?
assert_eq "0" "$rc" "audit_perms returns 0 when 600"
rm -rf "$TMP"

# drift: deployed entry passes (rc 0); missing deployment is flagged (rc 1)
TMP=$(mktempd); mkdir -p "$TMP/repo" "$TMP/home"; echo y > "$TMP/repo/d.conf"
printf 'd.conf\n' > "$TMP/repo/manifest"
ln -s "$TMP/repo/d.conf" "$TMP/home/d.conf"
rc=0; UNAME_OVERRIDE=Darwin HOME="$TMP/home" audit_drift "$TMP/repo" >/dev/null 2>&1 || rc=$?
assert_eq "0" "$rc" "audit_drift returns 0 when deployed"
rm "$TMP/home/d.conf"
out=$(UNAME_OVERRIDE=Darwin HOME="$TMP/home" audit_drift "$TMP/repo" 2>&1); rc=$?
echo "$out" | grep -q 'not deployed' && hit=yes || hit=no
assert_eq "yes" "$hit" "audit_drift flags undeployed entry"
assert_eq "1" "$rc" "audit_drift returns 1 on drift"
rm -rf "$TMP"

printf 'RESULT run=%s failed=%s\n' "$TESTS_RUN" "$TESTS_FAILED"
