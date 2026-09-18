#!/usr/bin/env bash

# T8: installs the versioned config/ tree onto the host.
#
# Two behaviours are mandatory:
#   1. Backups. Any existing destination file is backed up to
#      <dest>.bak.<UTC timestamp> before being overwritten. A user's config
#      is never silently destroyed.
#   2. Home substitution. Every installed text file contains the literal
#      marker __SPIDY_HOME__ where the author's home directory used to be;
#      it is replaced with the running user's real $HOME as the file is
#      installed, because MCP server `command` fields and hook command
#      strings are exec'd, not shell-expanded, so a literal $HOME would not
#      resolve there.
#
# This module always re-applies (see config_installed in lib/installer.sh):
# unlike a package module, re-running it is exactly how the host picks up an
# updated config/ tree, and every run still backs up whatever it replaces.

CONFIG_MARKER='__SPIDY_HOME__'

# Individual source -> $HOME-relative destination file mappings.
declare -A CONFIG_FILE_MAP=(
  [zsh/zshrc]='.zshrc'
  [zsh/p10k.zsh]='.p10k.zsh'
  [zellij/config.kdl]='.config/zellij/config.kdl'
  [herdr/config.toml]='.config/herdr/config.toml'
  [agents/claude/settings.template.json]='.claude/settings.json'
)

# Directory merges: source directory -> $HOME-relative destination directory.
declare -A CONFIG_DIRECTORY_MAP=(
  [agents/claude]='.claude'
  [agents/codex]='.codex'
  [agents/opencode]='.config/opencode'
  [agents/pi]='.pi'
)

# A file that must never be copied under its own (template) name when its
# containing directory is merged: it is installed separately, under its
# real installed name, via CONFIG_FILE_MAP above.
declare -A CONFIG_DIRECTORY_EXCLUDES=(
  [agents/claude]='settings.template.json'
)

config_root() {
  printf '%s/config' "$ROOT_DIR"
}

config_backup_path() {
  printf '%s.bak.%s' "$1" "$(date -u +%Y%m%dT%H%M%SZ)"
}

# Copies one file, substituting the __SPIDY_HOME__ marker for the real
# $HOME, and backing up any existing destination first.
config_install_file() {
  local source=$1 dest=$2 backup
  mkdir -p "$(dirname "$dest")"
  if [[ -e $dest || -L $dest ]]; then
    backup=$(config_backup_path "$dest")
    cp -a "$dest" "$backup"
    log "Backed up existing $dest to $backup"
  fi
  sed "s|$CONFIG_MARKER|$HOME|g" "$source" >"$dest"
  if [[ -x $source ]]; then
    chmod +x "$dest"
  fi
}

# Merges one source directory into a destination directory, preserving
# relative paths and skipping the module's declared exclusions.
config_install_directory() {
  local source_root=$1 dest_root=$2 exclude=${3:-} file rel
  mkdir -p "$dest_root"
  while IFS= read -r -d '' file; do
    rel=${file#"$source_root"/}
    [[ -n $exclude && $rel == "$exclude" ]] && continue
    config_install_file "$file" "$dest_root/$rel"
  done < <(find "$source_root" -type f -print0)
}

config_install_all() {
  local root source dest
  root=$(config_root)

  for source in "${!CONFIG_FILE_MAP[@]}"; do
    dest=${CONFIG_FILE_MAP[$source]}
    config_install_file "$root/$source" "$HOME/$dest"
  done

  for source in "${!CONFIG_DIRECTORY_MAP[@]}"; do
    dest=${CONFIG_DIRECTORY_MAP[$source]}
    config_install_directory "$root/$source" "$HOME/$dest" "${CONFIG_DIRECTORY_EXCLUDES[$source]:-}"
  done
}

# Read-only presence check used by `--audit`: true only when every mapped
# destination currently exists. Never mutates the host.
config_destination_present() {
  local root source dest file rel exclude
  root=$(config_root)

  for source in "${!CONFIG_FILE_MAP[@]}"; do
    dest=${CONFIG_FILE_MAP[$source]}
    [[ -e "$HOME/$dest" || -L "$HOME/$dest" ]] || return 1
  done

  for source in "${!CONFIG_DIRECTORY_MAP[@]}"; do
    dest=${CONFIG_DIRECTORY_MAP[$source]}
    exclude=${CONFIG_DIRECTORY_EXCLUDES[$source]:-}
    while IFS= read -r -d '' file; do
      rel=${file#"$root/$source"/}
      [[ -n $exclude && $rel == "$exclude" ]] && continue
      [[ -e "$HOME/$dest/$rel" || -L "$HOME/$dest/$rel" ]] || return 1
    done < <(find "$root/$source" -type f -print0)
  done
  return 0
}
