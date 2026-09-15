#!/usr/bin/env bash

WSL_DETECTED=0

validate_host() {
  if [[ $(uname -s) != Linux ]]; then
    printf '%s\n' 'Unsupported host: this installer requires Linux (Ubuntu 24.04 on WSL2 is supported).' >&2
    return 1
  fi
  if [[ ! -r /etc/os-release ]]; then
    printf '%s\n' 'Unsupported host: /etc/os-release is unavailable; Ubuntu 24.04 is required.' >&2
    return 1
  fi

  local ID='' VERSION_ID=''
  # /etc/os-release is the operating-system metadata format defined by systemd.
  # shellcheck disable=SC1091
  . /etc/os-release
  if [[ $ID != ubuntu || $VERSION_ID != 24.04 ]]; then
    printf 'Unsupported host: detected %s %s; this bootstrap supports Ubuntu 24.04 only.\n' "${ID:-unknown}" "${VERSION_ID:-unknown}" >&2
    return 1
  fi

  case "${WSL_INTEROP:-}:$(uname -r)" in
    *[Mm]icrosoft*|*WSL*) WSL_DETECTED=1 ;;
  esac

  if ((WSL_DETECTED)); then
    log 'Detected WSL. Docker requires WSL2 integration and usually systemd support in your WSL configuration.'
  else
    log 'Ubuntu 24.04 detected (native Linux).'
  fi
}
