# common.sh — shared helpers for the homedir-manager engine. Sourced, never executed.

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
hm_die() { printf 'homedir-manager: %s\n' "$1" >&2; exit "${2:-1}"; }
