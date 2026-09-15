#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/args.sh
source "$ROOT_DIR/lib/args.sh"
# shellcheck source=lib/modules.sh
source "$ROOT_DIR/lib/modules.sh"
# shellcheck source=lib/common.sh
source "$ROOT_DIR/lib/common.sh"
# shellcheck source=lib/platform.sh
source "$ROOT_DIR/lib/platform.sh"
# shellcheck source=lib/ui.sh
source "$ROOT_DIR/lib/ui.sh"
# shellcheck source=lib/installer.sh
source "$ROOT_DIR/lib/installer.sh"

print_summary() {
  local module
  printf '\n%s\n' 'Installation summary'
  printf '%s\n' 'Mandatory modules are always included:'
  for module in "${MANDATORY_MODULES[@]}"; do
    printf '  - %s\n' "$module"
  done
  printf '%s\n' 'Resolved plan:'
  for module in "${RESOLVED_MODULES[@]}"; do
    if [[ " ${MANDATORY_MODULES[*]} " == *" $module "* ]]; then
      printf '  - %s (mandatory)\n' "$module"
    else
      printf '  - %s\n' "$module"
    fi
  done
  printf '%s\n\n' 'Authentication, API keys, provider login, and SSH keys are manual and are not installed by this script.'
}

main() {
  parse_args "$@" || {
    usage >&2
    return 2
  }
  if ((SHOW_HELP)); then
    usage
    return 0
  fi
  if ((AUDIT)); then
    audit_environment
    return $?
  fi

  validate_host

  local -a selected=()
  if [[ -n $REQUESTED_MODULES ]]; then
    mapfile -t selected < <(expand_requested_modules "$REQUESTED_MODULES")
  elif ((NON_INTERACTIVE)); then
    selected=()
  else
    mapfile -t selected < <(choose_optional_modules)
  fi

  resolve_modules "${selected[@]}"
  print_summary
  if ((DRY_RUN)); then
    printf '%s\n' 'Dry-run command plan:'
    render_dry_run_plan
    printf '%s\n' 'Dry run complete: no installation commands were executed.'
    return 0
  fi
  if ! confirm_plan; then
    printf '%s\n' 'Installation cancelled.'
    return 0
  fi

  execute_plan
  cat <<'EOF'
Bootstrap complete. Open a new terminal, start Zsh, and run `p10k configure` if needed.
Run `gh auth login` and each provider's login command manually; configure SSH keys manually.
EOF
}

main "$@"
