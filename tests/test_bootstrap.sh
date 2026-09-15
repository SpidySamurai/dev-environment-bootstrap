#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../lib/modules.sh
source "$ROOT_DIR/lib/modules.sh"
# shellcheck source=../lib/args.sh
source "$ROOT_DIR/lib/args.sh"
# shellcheck source=../lib/common.sh
source "$ROOT_DIR/lib/common.sh"
# shellcheck source=../lib/ui.sh
source "$ROOT_DIR/lib/ui.sh"
# shellcheck source=../lib/installer.sh
source "$ROOT_DIR/lib/installer.sh"

failures=0

assert_eq() {
  local expected=$1 actual=$2 label=$3
  if [[ "$expected" != "$actual" ]]; then
    printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$label" "$expected" "$actual" >&2
    failures=$((failures + 1))
  else
    printf 'PASS: %s\n' "$label"
  fi
}

assert_contains() {
  local needle=$1 haystack=$2 label=$3
  if [[ "$haystack" != *"$needle"* ]]; then
    printf 'FAIL: %s\n  missing: %s\n' "$label" "$needle" >&2
    failures=$((failures + 1))
  else
    printf 'PASS: %s\n' "$label"
  fi
}

assert_not_contains() {
  local needle=$1 haystack=$2 label=$3
  if [[ "$haystack" == *"$needle"* ]]; then
    printf 'FAIL: %s\n  unexpected: %s\n' "$label" "$needle" >&2
    failures=$((failures + 1))
  else
    printf 'PASS: %s\n' "$label"
  fi
}

test_argument_parsing() {
  parse_args --dry-run --non-interactive --modules cli-modern,docker
  assert_eq "1" "$DRY_RUN" "--dry-run is parsed"
  assert_eq "1" "$NON_INTERACTIVE" "--non-interactive is parsed"
  assert_eq "cli-modern,docker" "$REQUESTED_MODULES" "--modules is parsed"

  parse_args --audit
  assert_eq "1" "$AUDIT" "--audit is parsed"
}

test_dependency_resolution() {
  resolve_modules docker agent-codex
  local resolved="${RESOLVED_MODULES[*]}"
  assert_contains "base-packages" "$resolved" "mandatory base packages are included"
  assert_contains "oh-my-zsh" "$resolved" "mandatory shell setup is included"
  assert_contains "container-prerequisites" "$resolved" "Docker prerequisites are included"
  assert_contains "node-nvm" "$resolved" "agent dependency is included"
  assert_contains "docker" "$resolved" "requested Docker module is included"
  assert_contains "agent-codex" "$resolved" "requested agent module is included"
}

test_dry_run_plan() {
  resolve_modules cli-modern docker
  local plan
  plan=$( 
    module_install_status() { return 1; }
    render_dry_run_plan
  )
  assert_contains "apt-get update" "$plan" "dry-run includes the apt update step for missing modules"
  assert_contains "cli-modern" "$plan" "dry-run includes selected missing optional modules"
  assert_contains "docker" "$plan" "dry-run includes selected missing Docker modules"
  assert_contains "sudo" "$plan" "dry-run makes privilege boundaries visible for missing modules"
}

test_dry_run_entrypoint() {
  local output
  output=$(bash "$ROOT_DIR/install.sh" --dry-run --non-interactive --modules cli-modern 2>&1)
  assert_contains "Dry run complete: no installation commands were executed." "$output" "dry-run entrypoint completes without installation"
}

test_dry_run_entrypoint_skips_managed_source_modules() {
  local output
  output=$(bash "$ROOT_DIR/install.sh" --dry-run --non-interactive --modules agent-pi 2>&1)

  assert_contains 'Skipping agent-pi: installed (managed source).' "$output" "dry-run entrypoint skips managed-source modules"
  assert_not_contains 'npm install -g @earendil-works/pi-coding-agent' "$output" "dry-run entrypoint does not plan managed-source module installation"
}

test_dry_run_plan_skips_alternate_source_modules() {
  local output
  output=$( 
    RESOLVED_MODULES=(multiplexers)
    zellij() { :; }
    tmux() { :; }
    packages_installed() { return 1; }
    render_dry_run_plan
  )

  assert_contains 'Skipping multiplexers: installed (alternate source).' "$output" "dry-run plan skips alternate-source modules"
  assert_not_contains 'apt-get install' "$output" "dry-run plan does not reinstall alternate-source modules"
}

directory_snapshot() {
  local directory=$1
  (
    cd "$directory"
    find . -mindepth 1 -printf '%P:%y:%s\n' | sort
  )
}

test_audit_entrypoint_is_read_only() {
  local audit_home="$ROOT_DIR/tests/fixtures/audit-home" mock_bin="$ROOT_DIR/tests/fixtures/mock-bin" before after output
  before=$(directory_snapshot "$audit_home")

  if ! output=$( 
    sudo() { printf '%s\n' 'FORBIDDEN: sudo'; return 99; }
    apt() { printf '%s\n' 'FORBIDDEN: apt'; return 99; }
    apt-get() { printf '%s\n' 'FORBIDDEN: apt-get'; return 99; }
    curl() { printf '%s\n' 'FORBIDDEN: curl'; return 99; }
    gum() { printf '%s\n' 'FORBIDDEN: gum'; return 99; }
    export -f sudo apt apt-get curl gum
    HOME="$audit_home" PATH="$mock_bin:$PATH" bash "$ROOT_DIR/install.sh" --audit 2>&1
  ); then
    printf '%s\n' 'FAIL: --audit exits successfully without installation' >&2
    failures=$((failures + 1))
    return
  fi

  after=$(directory_snapshot "$audit_home")
  assert_contains "Environment audit" "$output" "--audit prints an inventory heading"
  assert_contains "base-packages" "$output" "--audit lists mandatory modules"
  assert_contains "cli-modern" "$output" "--audit lists optional modules"
  assert_contains "manual/host configuration required" "$output" "--audit identifies manual checks"
  assert_contains "Summary" "$output" "--audit prints status counts"
  assert_eq "$before" "$after" "--audit leaves the audit HOME fixture unchanged"
  if [[ -e $audit_home/.npm ]]; then
    printf '%s\n' 'FAIL: --audit does not create an npm state directory' >&2
    failures=$((failures + 1))
  else
    printf '%s\n' 'PASS: --audit does not create an npm state directory'
  fi
  if [[ $output == *"FORBIDDEN:"* ]]; then
    printf '%s\n' 'FAIL: --audit does not invoke installation, interactive, or npm commands' >&2
    failures=$((failures + 1))
  else
    printf '%s\n' 'PASS: --audit does not invoke installation, interactive, or npm commands'
  fi
}

test_npm_module_probe_does_not_invoke_npm() {
  local mock_bin="$ROOT_DIR/tests/fixtures/mock-bin"
  if (PATH="$mock_bin" module_installed agent-gentle-ai); then
    printf '%s\n' 'FAIL: npm module detection does not invoke npm' >&2
    failures=$((failures + 1))
  else
    printf '%s\n' 'PASS: npm module detection does not invoke npm'
  fi
}

test_npm_module_probe_uses_node_prefix() {
  local node_prefix="$ROOT_DIR/tests/fixtures/node-prefix"
  if (PATH="$node_prefix/bin" module_installed agent-gentle-ai); then
    printf '%s\n' 'PASS: npm module detection finds packages from the Node prefix'
  else
    printf '%s\n' 'FAIL: npm module detection finds packages from the Node prefix' >&2
    failures=$((failures + 1))
  fi
}

test_command_shims_detect_alternate_optional_modules() {
  local output
  output=$( 
    zellij() { :; }
    tmux() { :; }
    docker() { :; }
    gh() { :; }
    gentle-ai() { :; }
    pi() { :; }
    codex() { :; }
    claude() { :; }
    opencode() { :; }
    herdr() { :; }
    packages_installed() { return 1; }
    npm_global_package_installed() { return 1; }

    audit_module_status multiplexers
    audit_module_status docker
    audit_module_status github-cli
    audit_module_status agent-gentle-ai
    audit_module_status agent-pi
    audit_module_status agent-codex
    audit_module_status agent-claude-code
    audit_module_status agent-opencode
    audit_module_status agent-herdr
  )
  assert_eq "$(printf '%s\n' \
    'installed (alternate source)' \
    'installed (alternate source)' \
    'installed (alternate source)' \
    'installed (alternate source)' \
    'installed (alternate source)' \
    'installed (alternate source)' \
    'installed (alternate source)' \
    'installed (alternate source)' \
    'installed (alternate source)')" "$output" "command shims identify alternate-source groups and agent CLIs"
}

test_group_command_evidence_reports_missing_members() {
  local output
  output=$( 
    zellij() { :; }
    packages_installed() { return 1; }
    MODULE_COMMANDS[multiplexers]='zellij tmux-not-found'
    audit_module_status multiplexers
  )
  assert_eq 'partial (alternate source; missing commands: tmux-not-found)' "$output" "partial groups name missing command evidence"
}

test_dry_run_execution_skips_alternate_source_modules() {
  local output
  output=$( 
    zellij() { :; }
    tmux() { :; }
    packages_installed() { return 1; }
    log() { printf '%s\n' "$*"; }
    DRY_RUN=1
    install_module multiplexers
  )
  assert_contains 'Skipping multiplexers: installed (alternate source).' "$output" "dry-run execution skips alternate-source modules"
  assert_not_contains 'apt-get install' "$output" "dry-run execution does not plan a reinstall for alternate-source modules"
}

test_live_execution_skips_alternate_source_modules() {
  local output
  output=$( 
    zellij() { :; }
    tmux() { :; }
    packages_installed() { return 1; }
    apt_install() { printf '%s\n' 'FORBIDDEN: apt install'; }
    log() { printf '%s\n' "$*"; }
    DRY_RUN=0
    install_module multiplexers
  )
  assert_contains 'Skipping multiplexers: installed (alternate source).' "$output" "live execution skips alternate-source modules"
  assert_not_contains 'FORBIDDEN: apt install' "$output" "live execution does not reinstall alternate-source modules"
}

test_unknown_module_rejected() {
  if resolve_modules unknown-module >/dev/null 2>&1; then
    printf '%s\n' 'FAIL: unknown modules are rejected' >&2
    failures=$((failures + 1))
  else
    printf '%s\n' 'PASS: unknown modules are rejected'
  fi
}

test_optional_selection_does_not_mutate_before_confirmation() {
  local output
  output=$(
    PATH=''
    run_best_effort_privileged() {
      printf 'privileged command: %s\n' "$*"
    }
    log() { :; }
    choose_optional_modules </dev/null
  )
  assert_eq "" "$output" "optional selection does not bootstrap Gum before confirmation"
}

test_dangling_zsh_config_paths_are_guarded() {
  local zshrc="$ROOT_DIR/tests/fixtures/dangling-zshrc"
  local p10k="$ROOT_DIR/tests/fixtures/dangling-p10k.zsh"
  if config_path_exists "$zshrc" && config_path_exists "$p10k"; then
    printf '%s\n' 'PASS: dangling Zsh configuration symlinks are guarded'
  else
    printf '%s\n' 'FAIL: dangling Zsh configuration symlinks are guarded' >&2
    failures=$((failures + 1))
  fi
}

test_module_path_probe_uses_catalog_metadata() {
  local original_home=$HOME
  local original_oh_my_zsh_path=${MODULE_PATH[oh-my-zsh]}
  local original_powerlevel10k_path=${MODULE_PATH[powerlevel10k]}

  HOME=$ROOT_DIR
  MODULE_PATH[oh-my-zsh]='$HOME'
  MODULE_PATH[powerlevel10k]='$HOME'

  if module_installed oh-my-zsh; then
    printf '%s\n' 'PASS: Oh My Zsh probe uses its catalog path'
  else
    printf '%s\n' 'FAIL: Oh My Zsh probe uses its catalog path' >&2
    failures=$((failures + 1))
  fi

  if module_installed powerlevel10k; then
    printf '%s\n' 'PASS: Powerlevel10k probe uses its catalog path'
  else
    printf '%s\n' 'FAIL: Powerlevel10k probe uses its catalog path' >&2
    failures=$((failures + 1))
  fi

  HOME=$original_home
  MODULE_PATH[oh-my-zsh]=$original_oh_my_zsh_path
  MODULE_PATH[powerlevel10k]=$original_powerlevel10k_path
}

test_argument_parsing
test_dependency_resolution
test_dry_run_plan
test_dry_run_entrypoint
test_dry_run_entrypoint_skips_managed_source_modules
test_dry_run_plan_skips_alternate_source_modules
test_audit_entrypoint_is_read_only
test_npm_module_probe_does_not_invoke_npm
test_npm_module_probe_uses_node_prefix
test_command_shims_detect_alternate_optional_modules
test_group_command_evidence_reports_missing_members
test_dry_run_execution_skips_alternate_source_modules
test_live_execution_skips_alternate_source_modules
test_unknown_module_rejected
test_optional_selection_does_not_mutate_before_confirmation
test_dangling_zsh_config_paths_are_guarded
test_module_path_probe_uses_catalog_metadata

if (( failures > 0 )); then
  exit 1
fi
