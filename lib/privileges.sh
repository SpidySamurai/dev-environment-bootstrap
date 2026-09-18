#!/usr/bin/env bash

# T2: privileges are negotiated exactly once, up front, before any module
# runs. Individual modules never trigger a fresh interactive sudo prompt.

PRIVILEGES_AVAILABLE=${PRIVILEGES_AVAILABLE:-0}
SUDO_KEEPALIVE_PID=""

has_readable_tty() {
  [[ -r /dev/tty ]]
}

sudo_available() {
  command -v sudo >/dev/null 2>&1
}

# Isolated so tests can exercise the negotiation logic without a real
# controlling terminal: /dev/tty is only opened here.
request_sudo_interactively() {
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

  if has_readable_tty; then
    if ! request_sudo_interactively; then
      log 'Failed to acquire sudo privileges; apt-based modules will report failed (no privileges).'
      return 1
    fi
  else
    if ! request_sudo_cached; then
      log 'No interactive terminal is available to request sudo, and no cached sudo credentials were found; apt-based modules will report failed (no privileges).'
      return 1
    fi
  fi

  PRIVILEGES_AVAILABLE=1
  start_sudo_keepalive
  return 0
}
