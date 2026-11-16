#!/usr/bin/env bash

# Installs the versioned config/ tree onto the host.
#
# Two behaviours are mandatory:
#   1. Backups. Any existing destination file is backed up to
#      <dest>.bak.<UTC timestamp> before being overwritten. A user's config
#      is never silently destroyed.
#   2. Home substitution. A text file may contain the literal marker
#      __SPIDY_HOME__ wherever it needs the user's home directory; it is
#      replaced with the running user's real $HOME as the file is installed,
#      for values that are exec'd rather than shell-expanded, where a literal
#      $HOME would not resolve.
#
# The tree covers the shell and terminal only. Coding-agent configuration is
# not shipped here: gentle-ai sets it up (`gentle-ai install`).
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

config_install_all() {
  local root source dest
  root=$(config_root)

  for source in "${!CONFIG_FILE_MAP[@]}"; do
    dest=${CONFIG_FILE_MAP[$source]}
    config_install_file "$root/$source" "$HOME/$dest"
  done
}

# Read-only presence check used by `--audit`: true only when every mapped
# destination currently exists. Never mutates the host.
config_destination_present() {
  local source dest
  for source in "${!CONFIG_FILE_MAP[@]}"; do
    dest=${CONFIG_FILE_MAP[$source]}
    [[ -e "$HOME/$dest" || -L "$HOME/$dest" ]] || return 1
  done
  return 0
}
