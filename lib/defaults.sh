# defaults.sh — delegate the `defaults` verb to the vendored Swift macos-defaults binary.
# Depends on common.sh (os_name). Sourced, never executed.

# defaults_cmd <apply|drift|capture> [args...]
defaults_cmd() {
  [ "$(os_name)" = "macos" ] || { printf 'homedir-manager: defaults is macOS only\n' >&2; return 2; }
  _bin=${HM_DEFAULTS_BIN:-}
  if [ -z "$_bin" ]; then
    # default location: macos/.build/release/macos-defaults relative to lib/
    # shellcheck disable=SC1007
    _bin=$(CDPATH= cd -- "$HM_LIB/../macos" 2>/dev/null && pwd -P)/.build/release/macos-defaults
  fi
  [ -x "$_bin" ] || { printf 'homedir-manager: macos-defaults not built (run bootstrap); expected %s\n' "$_bin" >&2; return 3; }
  "$_bin" "$@"
}
