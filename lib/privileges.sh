#!/usr/bin/env bash

# Privileges are negotiated exactly once, up front, before any module
# runs. Individual modules never trigger a fresh interactive sudo prompt.

PRIVILEGES_AVAILABLE=${PRIVILEGES_AVAILABLE:-0}
SUDO_KEEPALIVE_PID=""

# `[[ -r /dev/tty ]]` only checks file-permission bits — it can
# report true even when there is no real controlling terminal (e.g. under
# `curl | bash`, setsid, or a detached session), because the device node is
# still readable by the user even though opening it fails. Actually
# attempting to open it is the only reliable signal.
has_readable_tty() {
  { : </dev/tty; } 2>/dev/null
}

sudo_available() {
  command -v sudo >/dev/null 2>&1
}

# Isolated so tests can exercise the negotiation logic without a real
# controlling terminal: /dev/tty is only opened here.
request_sudo_interactively() {
  # The prompt must read from the terminal, not from sudo's privileges.
  # shellcheck disable=SC2024
  sudo -v </dev/tty
}

request_sudo_cached() {
  sudo -n -v 2>/dev/null
}

plan_requires_privileges() {
  local module
  for module in "${RESOLVED_MODULES[@]}"; do
    [[ ${MODULE_KIND[$module]-} == apt ]] && return 0
  done
  return 1
}

stop_sudo_keepalive() {
  if [[ -n $SUDO_KEEPALIVE_PID ]]; then
    kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    wait "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    SUDO_KEEPALIVE_PID=""
  fi
}

start_sudo_keepalive() {
  ( while true; do sudo -n -v 2>/dev/null; sleep 60; done ) &
  SUDO_KEEPALIVE_PID=$!
  trap 'stop_sudo_keepalive' EXIT
}

# Negotiates root privileges once, before any module runs. Never returns a
# failure to the caller as fatal: callers decide what to do (apt-based
# modules are skipped with a clear reason instead of aborting the run).
negotiate_privileges() {
  PRIVILEGES_AVAILABLE=0

  if ! plan_requires_privileges; then
    return 0
  fi

  if ! sudo_available; then
    log 'sudo is not available; apt-based modules will be skipped.'
    return 1
  fi

  # sudo -n -v is always tried first: it succeeds instantly for passwordless
  # sudo or already-cached credentials, and -n guarantees it never prompts,
  # so it is safe to attempt even with no controlling terminal at all. Only
  # if it fails, and a real controlling terminal actually exists, do we fall
  # back to an interactive prompt.
  if request_sudo_cached; then
    PRIVILEGES_AVAILABLE=1
    start_sudo_keepalive
    return 0
  fi

  if has_readable_tty; then
    if ! request_sudo_interactively; then
      log 'Failed to acquire sudo privileges; apt-based modules will report failed (no privileges).'
      return 1
    fi
  else
    log 'No interactive terminal is available to request sudo, and no cached sudo credentials were found; apt-based modules will report failed (no privileges).'
    return 1
  fi

  PRIVILEGES_AVAILABLE=1
  start_sudo_keepalive
  return 0
}
