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
# shellcheck source=lib/privileges.sh
source "$ROOT_DIR/lib/privileges.sh"
# shellcheck source=lib/config.sh
source "$ROOT_DIR/lib/config.sh"

print_summary() {
  render_module_panel
  printf '\n%s\n\n' 'Authentication, API keys, provider login, and SSH keys are manual and are not installed by this script.'
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
  mapfile -t selected < <(default_selected_modules)

  resolve_modules "${selected[@]}"
  print_summary
  if ((DRY_RUN)); then
    printf '%s\n' 'Dry-run command plan:'
    render_dry_run_plan
    printf '%s\n' 'Dry run complete: no installation commands were executed.'
    return 0
  fi
  if ! confirm_full_install; then
    printf '%s\n' 'Installation cancelled.'
    return 0
  fi

  negotiate_privileges || true

  local exec_rc=0
  execute_plan || exec_rc=$?
  if ((exec_rc == 0)); then
    cat <<'EOF'
Bootstrap complete. Open a new terminal, start Zsh, and run `p10k configure` if needed.
Run `gh auth login` and each provider's login command manually; configure SSH keys manually.
EOF
  else
    printf '%s\n' 'Bootstrap finished with failures. Review the installation report above.' >&2
  fi
  return "$exec_rc"
}

main "$@"
