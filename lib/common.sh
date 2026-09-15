#!/usr/bin/env bash

log() {
  printf '%s\n' "$*" >&2
}

print_command() {
  local argument
  printf '[dry-run]'
  for argument in "$@"; do
    printf ' %q' "$argument"
  done
  printf '\n'
}

run() {
  if ((DRY_RUN)); then
    print_command "$@"
    return 0
  fi
  "$@"
}

# All privileged commands pass through these two functions.
run_privileged() {
  run sudo -- "$@"
}

run_best_effort_privileged() {
  if ((DRY_RUN)); then
    print_command sudo -- "$@"
    return 1
  fi
  if ! sudo -- "$@"; then
    log "Optional command failed: sudo $*"
    return 1
  fi
}

apt_update() {
  run_privileged apt-get update
}

apt_install() {
  run_privileged apt-get install -y "$@"
}

packages_installed() {
  local package
  for package in "$@"; do
    [[ $(dpkg-query --show --showformat='${db:Status-Status}' "$package" 2>/dev/null) == installed ]] || return 1
  done
}

run_remote_script() {
  local url=$1 interpreter=$2
  shift 2
  # The command is only called outside dry-run; curl refuses HTTP, follows HTTPS
  # redirects, reports errors, and retries transient network failures.
  curl --fail --show-error --location --proto '=https' --tlsv1.2 --retry 3 --retry-delay 2 "$url" | env "$@" "$interpreter"
}

source_nvm() {
  local nvm_dir=${NVM_DIR:-"$HOME/.nvm"}
  if [[ -s "$nvm_dir/nvm.sh" ]]; then
    # shellcheck disable=SC1090
    . "$nvm_dir/nvm.sh"
    return 0
  fi
  log 'nvm was not found after installation.'
  return 1
}
