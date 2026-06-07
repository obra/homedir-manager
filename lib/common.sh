# common.sh — shared helpers for the homedir-manager engine. Sourced, never executed.
# shellcheck disable=SC2034  # HM_MARKER/HM_REL/HM_TAG/HM_MERGE are consumed by the scripts that source this.

# Marker filename that opts a directory in as a managed content repo.
HM_MARKER='.homedir-manager.conf'

# os_name — map uname (overridable for tests) to macos/linux/other.
os_name() {
  case "${UNAME_OVERRIDE:-$(uname -s)}" in
    Darwin) echo macos ;;
    Linux)  echo linux ;;
    *)      echo other ;;
  esac
}

# hm_die — print to stderr and exit non-zero.
hm_die() { printf 'homedir-manager: %s\n' "${1:-}" >&2; exit "${2:-1}"; }

# parse_manifest_line <line> — strip the trailing comment and the optional trailing OS tag
# (macos|linux), leaving the repo-relative path (which MAY contain spaces, e.g. paths under
# "~/Library/Application Support/"). Sets HM_REL (path) and HM_TAG (macos|linux|''). Returns 1
# for blank/comment-only lines so callers can `parse_manifest_line "$l" || continue`.
parse_manifest_line() {
  HM_MERGE=''
  _l=${1%%#*}
  _l=${_l%"${_l##*[![:space:]]}"}              # rtrim
  [ -z "$_l" ] && { HM_REL=''; HM_TAG=''; return 1; }
  # Explicit merge directive: a leading `merge-children` keyword. Mode is NEVER selected by
  # punctuation (see the trailing-slash guard below) — that is the rsync `src/` vs `src` footgun.
  case "$_l" in
    merge-children[[:space:]]*)
      HM_MERGE=1
      _l=${_l#merge-children}
      _l=${_l#"${_l%%[![:space:]]*}"}          # ltrim the whitespace after the keyword
      ;;
  esac
  case "$_l" in
    *[[:space:]]macos) HM_TAG=macos; _l=${_l%macos} ;;
    *[[:space:]]linux) HM_TAG=linux; _l=${_l%linux} ;;
    *)                 HM_TAG='' ;;
  esac
  HM_REL=${_l%"${_l##*[![:space:]]}"}          # rtrim whitespace left before the stripped tag
  [ -z "$HM_REL" ] && return 1
  case "$HM_REL" in
    */) hm_die "trailing slash on '$HM_REL'; to merge a directory's children use the 'merge-children' directive" ;;
  esac
  return 0
}
