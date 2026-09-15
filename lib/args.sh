#!/usr/bin/env bash

DRY_RUN=0
NON_INTERACTIVE=0
ASSUME_YES=0
REQUESTED_MODULES=""
SHOW_HELP=0
AUDIT=0

usage() {
  cat <<'EOF'
Usage: ./install.sh [options]

Options:
  --dry-run                 Print the installation plan without changing the host.
  --non-interactive         Do not prompt; install mandatory modules and --modules.
  --modules <ids|all>       Comma-separated optional module IDs, or "all".
  --yes                     Confirm the displayed plan without prompting.
  --audit                   Inspect module status without changing the host.
  --help                    Show this help text.
EOF
}

parse_args() {
  DRY_RUN=0
  NON_INTERACTIVE=0
  ASSUME_YES=0
  REQUESTED_MODULES=""
  SHOW_HELP=0
  AUDIT=0

  while (($#)); do
    case "$1" in
      --dry-run) DRY_RUN=1 ;;
      --non-interactive) NON_INTERACTIVE=1 ;;
      --yes) ASSUME_YES=1 ;;
      --audit) AUDIT=1 ;;
      --modules)
        shift
        if (($# == 0)) || [[ -z "$1" ]]; then
          printf '%s\n' "--modules requires a comma-separated value or all." >&2
          return 2
        fi
        REQUESTED_MODULES=$1
        ;;
      --help|-h) SHOW_HELP=1 ;;
      *)
        printf 'Unknown option: %s\n' "$1" >&2
        return 2
        ;;
    esac
    shift
  done

  if ((NON_INTERACTIVE)) && ((SHOW_HELP == 0)); then
    ASSUME_YES=1
  fi
}
