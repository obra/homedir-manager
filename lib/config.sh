# config.sh — locate managed content repos. Sourced, never executed.
# Depends on common.sh (HM_MARKER).

# hm_base — base directory scanned for managed repos.
hm_base() { printf '%s\n' "${HOMEDIR_MANAGER_BASE:-$HOME/git}"; }

# discover_repos [base] — print the physical path of each immediate subdirectory
# of base that contains the marker file, one per line, in sorted glob order.
discover_repos() {
  _base=${1:-$(hm_base)}
  [ -d "$_base" ] || return 0
  for _d in "$_base"/*/; do
    [ -f "$_d$HM_MARKER" ] || continue
    # shellcheck disable=SC1007
    (CDPATH= cd -- "$_d" && pwd -P)
  done
}
