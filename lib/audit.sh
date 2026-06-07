# audit.sh — leak / drift / perms checks across managed repos. Sourced, never executed.
# Depends on common.sh (os_name) and config.sh (discover_repos, hm_base).

# Literal credential shapes that must never be committed.
HM_SECRET_PATTERNS='-----BEGIN [A-Z ]*PRIVATE KEY-----|ops_[A-Za-z0-9]{40,}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|sk-[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}'

# os_perm <file> — octal perms; Linux stat -c first, macOS stat -f fallback.
os_perm() { stat -c '%a' "$1" 2>/dev/null || stat -f '%A' "$1" 2>/dev/null; }

# audit_secrets <repo> — grep tracked files for credential shapes. Returns 1 on any hit.
audit_secrets() {
  _repo=$1; _name=$(basename "$_repo")
  _hits=$(git -C "$_repo" grep -nIE -e "$HM_SECRET_PATTERNS" -- ':!docs/*' 2>/dev/null || true)
  _bad=$(git -C "$_repo" ls-files 2>/dev/null | grep -nE '(^|/)\.env|\.(pem|key|p12|pfx)$|credentials|\.crt$' || true)
  _rc=0
  if [ -n "$_hits" ]; then printf '[%s] possible secret(s) — investigate + ROTATE:\n%s\n' "$_name" "$_hits"; _rc=1; fi
  if [ -n "$_bad" ]; then printf '[%s] suspicious tracked filename(s): %s\n' "$_name" "$(printf '%s' "$_bad" | tr '\n' ' ')"; _rc=1; fi
  return $_rc
}

# audit_drift <repo> — every manifest entry for this OS is symlinked into $HOME. Returns 1 on drift.
# For a merge-children entry, each child must be linked AND no dangling orphan (a symlink in the
# target dir pointing into the repo dir whose target was removed) may remain.
audit_drift() {
  _repo=$1; _name=$(basename "$_repo"); _os=$(os_name); _rc=0
  [ -f "$_repo/manifest" ] || return 0
  while IFS= read -r _line || [ -n "$_line" ]; do
    parse_manifest_line "$_line" || continue
    _rel=$HM_REL; _tag=$HM_TAG
    [ -n "$_tag" ] && [ "$_tag" != "$_os" ] && continue

    if [ "${HM_MERGE:-}" = 1 ]; then
      _mdir="$_repo/$_rel"
      [ -d "$_mdir" ] || { printf '[%s] merge dir missing from repo: %s\n' "$_name" "$_rel"; _rc=1; continue; }
      for _child in "$_mdir"/*; do
        [ -e "$_child" ] || [ -L "$_child" ] || continue
        _cr="$_rel/$(basename "$_child")"; _cs="$_repo/$_cr"; _cd="$HOME/$_cr"
        # shellcheck disable=SC3013  # -ef is a universal extension
        if [ -L "$_cd" ] && [ "$_cd" -ef "$_cs" ]; then :; else
          printf '[%s] not deployed (run install): %s\n' "$_name" "$_cr"; _rc=1
        fi
      done
      if [ -d "$HOME/$_rel" ]; then
        for _link in "$HOME/$_rel"/*; do
          [ -L "$_link" ] || continue
          case "$(readlink "$_link")" in
            "$_mdir"/*) [ -e "$_link" ] || { printf '[%s] orphaned symlink (repo child removed): %s\n' "$_name" "${_link#"$HOME/"}"; _rc=1; } ;;
          esac
        done
      fi
      continue
    fi

    _src="$_repo/$_rel"; _dest="$HOME/$_rel"
    [ -e "$_src" ] || { printf '[%s] manifest entry missing from repo: %s\n' "$_name" "$_rel"; _rc=1; continue; }
    # shellcheck disable=SC3013  # -ef is a universal extension (bash 3.2, dash, busybox, ksh)
    if [ -L "$_dest" ] && [ "$_dest" -ef "$_src" ]; then :; else
      printf '[%s] not deployed (run install): %s\n' "$_name" "$_rel"; _rc=1
    fi
  done < "$_repo/manifest"
  return $_rc
}

# audit_perms <repo> — HM_SECRET_FILES (from the repo marker) must be 600. Returns 1 on violation.
# The marker is sourced inside a `set +e` subshell so a malformed marker cannot abort the audit.
audit_perms() {
  _repo=$1; _rc=0
  # shellcheck disable=SC1090  # the marker is a user-supplied runtime path, not statically known
  _secret_files=$( set +e; [ -f "$_repo/$HM_MARKER" ] && . "$_repo/$HM_MARKER"; printf '%s' "${HM_SECRET_FILES:-}" )
  for _f in $_secret_files; do
    [ -e "$_f" ] || continue
    _p=$(os_perm "$_f")
    [ "$_p" = "600" ] || { printf '%s is %s (want 600)\n' "$_f" "$_p"; _rc=1; }
  done
  return $_rc
}

# audit_all [base] [checks] — run the named checks across discovered repos. `checks` is a
# space-separated subset of "secrets drift perms" (default: all three). Returns 1 if any finding.
audit_all() {
  _base=${1:-$(hm_base)}
  _checks=${2:-secrets drift perms}
  _findings=0
  for _repo in $(discover_repos "$_base"); do
    # shellcheck disable=SC2086  # _checks is an intentional space-separated list
    for _chk in $_checks; do
      "audit_$_chk" "$_repo" || _findings=$((_findings+1))
    done
  done
  [ "$_findings" -eq 0 ] && printf 'PASS — no findings\n' || printf 'FAIL — %s finding(s)\n' "$_findings"
  [ "$_findings" -eq 0 ]
}
