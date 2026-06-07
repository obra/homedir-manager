# hooks.sh — install the pre-push audit hook into managed content repos. Sourced, never executed.
# Depends on common.sh and config.sh (discover_repos, hm_base).

# install_hooks [base] [hook_src] — symlink the pre-push hook into each discovered repo's
# .git/hooks/pre-push. A repo whose pre-push already exists and is NOT our symlink is left
# untouched (we never clobber a hand-written hook). hook_src defaults to share/hooks/pre-push.
install_hooks() {
  _base=${1:-$(hm_base)}
  _src=${2:-}
  if [ -z "$_src" ]; then
    # shellcheck disable=SC1007
    _src=$(CDPATH= cd -- "$HM_LIB/../share/hooks" 2>/dev/null && pwd -P)/pre-push
  fi
  [ -f "$_src" ] || { printf 'homedir-manager: hook source not found: %s\n' "$_src" >&2; return 1; }
  _n=0
  for _repo in $(discover_repos "$_base"); do
    [ -d "$_repo/.git" ] || continue
    _dest="$_repo/.git/hooks/pre-push"
    if [ -e "$_dest" ] && [ ! -L "$_dest" ]; then
      printf 'homedir-manager: %s exists and is not ours — leaving it\n' "$_dest" >&2; continue
    fi
    mkdir -p "$_repo/.git/hooks"
    ln -sf "$_src" "$_dest"
    printf 'installed pre-push hook: %s\n' "$_dest"
    _n=$((_n + 1))
  done
  [ "$_n" -gt 0 ] || printf 'homedir-manager: no managed repos with a .git found under %s\n' "$_base" >&2
  return 0
}
