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

  set -f
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%%#*}
    # shellcheck disable=SC2086
    set -- $line
    [ "$#" -eq 0 ] && continue
    rel=$1; tag=${2:-}
    if [ -n "$tag" ] && [ "$tag" != "$_os" ]; then continue; fi

    src="$_repo/$rel"; dest="$HOME/$rel"
    if [ ! -e "$src" ] && [ ! -L "$src" ]; then
      printf 'MISSING  %s (not in %s)\n' "$rel" "$_repo"; _missing=$((_missing+1)); continue
    fi
    if [ -L "$dest" ] && [ "$dest" -ef "$src" ]; then _skipped=$((_skipped+1)); continue; fi
    if [ "$_dry" = 1 ]; then
      if [ -e "$dest" ] || [ -L "$dest" ]; then printf 'WOULD BACKUP+LINK  %s\n' "$rel"
      else printf 'WOULD LINK  %s\n' "$rel"; fi
      continue
    fi
    mkdir -p "$(dirname "$dest")"
    if [ -e "$dest" ] || [ -L "$dest" ]; then
      mkdir -p "$(dirname "$_backup/$rel")"; mv "$dest" "$_backup/$rel"
      _backed=$((_backed+1)); printf 'BACKUP   %s -> %s\n' "$rel" "$_backup/$rel"
    fi
    ln -s "$src" "$dest"; _linked=$((_linked+1)); printf 'LINK     %s\n' "$rel"
  done < "$_manifest"
  set +f

  printf 'linked=%s skipped=%s backed_up=%s missing=%s\n' "$_linked" "$_skipped" "$_backed" "$_missing"
}
