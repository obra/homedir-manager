# audit.sh — leak / drift / perms checks across managed repos. Sourced, never executed.
# Depends on common.sh (os_name) and config.sh (discover_repos, hm_base).

# Literal credential shapes that must never be committed.
HM_SECRET_PATTERNS='-----BEGIN [A-Z ]*PRIVATE KEY-----|ops_[A-Za-z0-9]{40,}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|sk-[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}'

# os_perm <file> — octal perms; Linux stat -c first, macOS stat -f fallback.
os_perm() { stat -c '%a' "$1" 2>/dev/null || stat -f '%A' "$1" 2>/dev/null; }

# audit_secrets <repo> — grep tracked files for credential shapes. Returns 1 on any hit.
audit_secrets() {
  repo=$1; name=$(basename "$repo")
  hits=$(git -C "$repo" grep -nIE -e "$HM_SECRET_PATTERNS" -- ':!docs/*' 2>/dev/null || true)
  bad=$(git -C "$repo" ls-files 2>/dev/null | grep -nE '(^|/)\.env|\.(pem|key|p12|pfx)$|credentials|\.crt$' || true)
  rc=0
  if [ -n "$hits" ]; then printf '[%s] possible secret(s) — investigate + ROTATE:\n%s\n' "$name" "$hits"; rc=1; fi
  if [ -n "$bad" ]; then printf '[%s] suspicious tracked filename(s): %s\n' "$name" "$(printf '%s' "$bad" | tr '\n' ' ')"; rc=1; fi
  return $rc
}

# audit_drift <repo> — every manifest entry for this OS is symlinked into $HOME. Returns 1 on drift.
audit_drift() {
  repo=$1; name=$(basename "$repo"); os=$(os_name); rc=0
  [ -f "$repo/manifest" ] || return 0
  set -f
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%%#*}; # shellcheck disable=SC2086
    set -- $line; [ "$#" -eq 0 ] && continue
    rel=$1; tag=${2:-}
    [ -n "$tag" ] && [ "$tag" != "$os" ] && continue
    src="$repo/$rel"; dest="$HOME/$rel"
    [ -e "$src" ] || { printf '[%s] manifest entry missing from repo: %s\n' "$name" "$rel"; rc=1; continue; }
    if [ -L "$dest" ] && [ "$dest" -ef "$src" ]; then :; else
      printf '[%s] not deployed (run install): %s\n' "$name" "$rel"; rc=1
    fi
  done < "$repo/manifest"
  set +f
  return $rc
}

# audit_perms <repo> — HM_SECRET_FILES (from the repo marker) must be 600. Returns 1 on violation.
audit_perms() {
  repo=$1; rc=0
  HM_SECRET_FILES=''
  # shellcheck disable=SC1090
  [ -f "$repo/$HM_MARKER" ] && . "$repo/$HM_MARKER"
  for f in $HM_SECRET_FILES; do
    [ -e "$f" ] || continue
    p=$(os_perm "$f")
    [ "$p" = "600" ] || { printf '%s is %s (want 600)\n' "$f" "$p"; rc=1; }
  done
  return $rc
}

# audit_all [base] — run all checks across discovered repos. Returns 1 if any finding.
audit_all() {
  base=${1:-$(hm_base)}; findings=0
  for repo in $(discover_repos "$base"); do
    audit_secrets "$repo" || findings=$((findings+1))
    audit_drift   "$repo" || findings=$((findings+1))
    audit_perms   "$repo" || findings=$((findings+1))
  done
  [ "$findings" -eq 0 ] && printf 'PASS — no findings\n' || printf 'FAIL — %s finding(s)\n' "$findings"
  [ "$findings" -eq 0 ]
}
