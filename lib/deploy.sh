# deploy.sh — symlink a content repo's manifest entries into $HOME. Sourced, never executed.
# Depends on common.sh (os_name, parse_manifest_line).

# _deploy_path <rel> — symlink $HOME/<rel> -> $_repo/<rel>, clobber-safe. Reads $_repo/$_dry/
# $_backup and bumps deploy_repo's accumulators ($_linked/$_skipped/$_backed/$_missing).
_deploy_path() {
  _r=$1; _s="$_repo/$_r"; _d="$HOME/$_r"
  if [ ! -e "$_s" ] && [ ! -L "$_s" ]; then
    printf 'MISSING  %s (not in %s)\n' "$_r" "$_repo"; _missing=$((_missing+1)); return
  fi
  # shellcheck disable=SC3013  # -ef is a universal extension (bash 3.2, dash, busybox, ksh)
  if [ -L "$_d" ] && [ "$_d" -ef "$_s" ]; then _skipped=$((_skipped+1)); return; fi
  if [ "$_dry" = 1 ]; then
    if [ -e "$_d" ] || [ -L "$_d" ]; then printf 'WOULD BACKUP+LINK  %s\n' "$_r"
    else printf 'WOULD LINK  %s\n' "$_r"; fi
    return
  fi
  mkdir -p "$(dirname "$_d")"
  if [ -e "$_d" ] || [ -L "$_d" ]; then
    mkdir -p "$(dirname "$_backup/$_r")"; mv "$_d" "$_backup/$_r"
    _backed=$((_backed+1)); printf 'BACKUP   %s -> %s\n' "$_r" "$_backup/$_r"
  fi
  ln -s "$_s" "$_d"; _linked=$((_linked+1)); printf 'LINK     %s\n' "$_r"
}

# deploy_repo <repo_dir> [--dry-run]
deploy_repo() {
  _repo=$1; _dry=0
  [ "${2:-}" = "--dry-run" ] && _dry=1
  _os=$(os_name)
  _manifest="$_repo/manifest"
  [ -f "$_manifest" ] || { printf 'homedir-manager: no manifest in %s\n' "$_repo" >&2; return 1; }

  _ts=$(date +%Y%m%d-%H%M%S)
  _backup="$HOME/.dotfiles-backup/$_ts"
  _linked=0; _skipped=0; _backed=0; _missing=0

  while IFS= read -r _line || [ -n "$_line" ]; do
    parse_manifest_line "$_line" || continue
    _rel=$HM_REL; _tag=$HM_TAG
    if [ -n "$_tag" ] && [ "$_tag" != "$_os" ]; then continue; fi

    if [ "${HM_MERGE:-}" = 1 ]; then
      _mdir="$_repo/$_rel"
      if [ ! -d "$_mdir" ]; then
        printf 'MISSING  %s (merge dir not in %s)\n' "$_rel" "$_repo"; _missing=$((_missing+1)); continue
      fi
      [ "$_dry" = 1 ] || mkdir -p "$HOME/$_rel"
      for _child in "$_mdir"/*; do
        [ -e "$_child" ] || [ -L "$_child" ] || continue   # empty-glob guard
        _deploy_path "$_rel/$(basename "$_child")"
      done
    else
      _deploy_path "$_rel"
    fi
  done < "$_manifest"

  printf 'linked=%s skipped=%s backed_up=%s missing=%s\n' "$_linked" "$_skipped" "$_backed" "$_missing"
}
