# deploy.sh — symlink a content repo's manifest entries into $HOME. Sourced, never executed.
# Depends on common.sh (os_name).

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

    _src="$_repo/$_rel"; _dest="$HOME/$_rel"
    if [ ! -e "$_src" ] && [ ! -L "$_src" ]; then
      printf 'MISSING  %s (not in %s)\n' "$_rel" "$_repo"; _missing=$((_missing+1)); continue
    fi
    if [ -L "$_dest" ] && [ "$_dest" -ef "$_src" ]; then _skipped=$((_skipped+1)); continue; fi
    if [ "$_dry" = 1 ]; then
      if [ -e "$_dest" ] || [ -L "$_dest" ]; then printf 'WOULD BACKUP+LINK  %s\n' "$_rel"
      else printf 'WOULD LINK  %s\n' "$_rel"; fi
      continue
    fi
    mkdir -p "$(dirname "$_dest")"
    if [ -e "$_dest" ] || [ -L "$_dest" ]; then
      mkdir -p "$(dirname "$_backup/$_rel")"; mv "$_dest" "$_backup/$_rel"
      _backed=$((_backed+1)); printf 'BACKUP   %s -> %s\n' "$_rel" "$_backup/$_rel"
    fi
    ln -s "$_src" "$_dest"; _linked=$((_linked+1)); printf 'LINK     %s\n' "$_rel"
  done < "$_manifest"

  printf 'linked=%s skipped=%s backed_up=%s missing=%s\n' "$_linked" "$_skipped" "$_backed" "$_missing"
}
