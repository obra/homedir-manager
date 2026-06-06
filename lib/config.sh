# config.sh — locate managed content repos. Sourced, never executed.
# Depends on common.sh (HM_MARKER).

# hm_base — base directory scanned for managed repos.
hm_base() { printf '%s\n' "${HOMEDIR_MANAGER_BASE:-$HOME/git}"; }

# discover_repos [base] — print the physical path of each immediate subdirectory
# of base that contains the marker file, one per line, in sorted glob order.
discover_repos() {
  base=${1:-$(hm_base)}
  [ -d "$base" ] || return 0
  for d in "$base"/*/; do
    [ -f "$d$HM_MARKER" ] || continue
    (CDPATH= cd -- "$d" && pwd -P)
  done
}
