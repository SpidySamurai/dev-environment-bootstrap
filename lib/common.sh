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

# Usage: run_remote_script <url> <interpreter> [ENV=VALUE ...] [-- <interpreter args> ...]
#
# Everything before `--` is an environment assignment for `env`; everything
# after it is an argument for the interpreter itself. The distinction matters:
# passing interpreter flags as if they were assignments makes `env` fail with
# "invalid option", which closes the pipe and surfaces as the misleading
# `curl: (23) Failure writing output to destination`.
run_remote_script() {
  local url=$1 interpreter=$2 argument
  shift 2

  local -a env_assignments=() interpreter_args=()
  local past_separator=0
  for argument in "$@"; do
    if ((past_separator)); then
      interpreter_args+=("$argument")
    elif [[ $argument == -- ]]; then
      past_separator=1
    else
      env_assignments+=("$argument")
    fi
  done

  # The command is only called outside dry-run; curl refuses HTTP, follows HTTPS
  # redirects, reports errors, and retries transient network failures.
  curl --fail --show-error --location --proto '=https' --tlsv1.2 --retry 3 --retry-delay 2 "$url" \
    | env "${env_assignments[@]}" "$interpreter" "${interpreter_args[@]}"
}

source_nvm() {
  local nvm_dir=${NVM_DIR:-"$HOME/.nvm"}
  if [[ -s "$nvm_dir/nvm.sh" ]]; then
    # nvm.sh lives on the host, not in this repository.
    # shellcheck source=/dev/null
    . "$nvm_dir/nvm.sh"
    return 0
  fi
  log 'nvm was not found after installation.'
  return 1
}
