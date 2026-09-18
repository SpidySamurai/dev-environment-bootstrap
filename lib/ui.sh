#!/usr/bin/env bash

# T3: the default path is a single yes/no confirmation, not a multi-select
# menu. All interactive reads come from /dev/tty (never stdin), so
# `curl -fsSL <url> | bash` keeps working: stdin is the piped script, and
# only /dev/tty can carry a real answer.

# Isolated so tests can exercise confirm_full_install without a real
# controlling terminal: /dev/tty is only opened here.
prompt_full_install_confirmation() {
  local answer
  printf '%s' 'Install the complete Spidy environment? [Y/n] ' >/dev/tty
  read -r answer </dev/tty
  printf '%s' "$answer"
}

confirm_full_install() {
  ((ASSUME_YES)) && return 0
  ((NON_INTERACTIVE)) && return 0

  if ! has_readable_tty; then
    printf '%s\n' 'No interactive terminal is available; re-run with --yes or --non-interactive to proceed without a prompt.' >&2
    return 1
  fi

  local answer
  answer=$(prompt_full_install_confirmation)
  [[ -z $answer || $answer =~ ^[Yy]([Ee][Ss])?$ ]]
}
