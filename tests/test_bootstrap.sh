#!/usr/bin/env bash
# Tests define stub functions that the sourced code under test calls (SC2329,
# SC2032), and change globals inside $( ) subshells on purpose so each test
# leaves no state behind (SC2030, SC2031).
# shellcheck disable=SC2329,SC2032,SC2030,SC2031
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
# shellcheck source=../lib/privileges.sh
source "$ROOT_DIR/lib/privileges.sh"
# shellcheck source=../bootstrap.sh
source "$ROOT_DIR/bootstrap.sh"
# shellcheck source=../lib/config.sh
source "$ROOT_DIR/lib/config.sh"

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

# Counts panel bullet lines ("  - <title>...") whose title is exactly
# $title, not merely a substring match somewhere in a longer title (e.g.
# "herdr" is a literal substring of the unrelated spidy-config title).
count_module_title_lines() {
  local title=$1 haystack=$2 line remainder n=0
  while IFS= read -r line; do
    [[ "$line" == '  - '* ]] || continue
    remainder=${line#  - }
    if [[ "$remainder" == "$title" || "$remainder" == "$title "* ]]; then
      n=$((n + 1))
    fi
  done <<<"$haystack"
  printf '%s' "$n"
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
  resolve_modules docker agent-pi lazygit
  local resolved="${RESOLVED_MODULES[*]}"
  assert_contains "base-packages" "$resolved" "mandatory base packages are included"
  assert_contains "oh-my-zsh" "$resolved" "mandatory shell setup is included"
  assert_contains "container-prerequisites" "$resolved" "Docker prerequisites are included"
  assert_contains "node-nvm" "$resolved" "the nvm-based agent dependency is included"
  assert_contains "go" "$resolved" "the go dependency for lazygit is included"
  assert_contains "docker" "$resolved" "requested Docker module is included"
  assert_contains "agent-pi" "$resolved" "requested agent module is included"
  assert_contains "lazygit" "$resolved" "requested lazygit module is included"
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
  local output fake_root
  # Fake a global npm install of Pi (package and command), so the test does not
  # depend on whether the machine running it happens to have Pi installed.
  fake_root=$(mktemp -d)
  mkdir -p "$fake_root/node_modules/@earendil-works/pi-coding-agent" "$fake_root/bin"
  printf '%s\n' '{"name":"@earendil-works/pi-coding-agent"}' \
    >"$fake_root/node_modules/@earendil-works/pi-coding-agent/package.json"
  printf '%s\n' '#!/bin/sh' 'exit 0' >"$fake_root/bin/pi"
  chmod +x "$fake_root/bin/pi"
  output=$(NODE_PATH="$fake_root/node_modules" PATH="$fake_root/bin:$PATH" \
    bash "$ROOT_DIR/install.sh" --dry-run --non-interactive --modules agent-pi 2>&1)
  rm -rf "$fake_root"

  assert_contains 'Skipping agent-pi: installed (managed source).' "$output" "dry-run entrypoint skips managed-source modules"
  assert_not_contains 'npm install -g @earendil-works/pi-coding-agent' "$output" "dry-run entrypoint does not plan managed-source module installation"
}

test_dry_run_plan_skips_alternate_source_modules() {
  local output
  output=$(
    RESOLVED_MODULES=(tmux)
    tmux() { :; }
    packages_installed() { return 1; }
    render_dry_run_plan
  )

  assert_contains 'Skipping tmux: installed (alternate source).' "$output" "dry-run plan skips alternate-source modules"
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
  local audit_home mock_bin="$ROOT_DIR/tests/fixtures/mock-bin" before after output
  # A real, non-empty HOME, so the before/after snapshot can detect writes.
  audit_home=$(mktemp -d)
  mkdir -p "$audit_home/.config"
  printf '%s\n' '# existing user config' >"$audit_home/.zshrc"
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
    rm -rf "$audit_home"
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
  rm -rf "$audit_home"
}

test_npm_module_probe_does_not_invoke_npm() {
  local mock_bin="$ROOT_DIR/tests/fixtures/mock-bin"
  if (PATH="$mock_bin" npm_global_package_installed gentle-ai); then
    printf '%s\n' 'FAIL: npm module detection does not invoke npm' >&2
    failures=$((failures + 1))
  else
    printf '%s\n' 'PASS: npm module detection does not invoke npm'
  fi
}

test_npm_module_probe_uses_node_prefix() {
  local node_prefix="$ROOT_DIR/tests/fixtures/node-prefix"
  if (PATH="$node_prefix/bin" npm_global_package_installed gentle-ai); then
    printf '%s\n' 'PASS: npm module detection finds packages from the Node prefix'
  else
    printf '%s\n' 'FAIL: npm module detection finds packages from the Node prefix' >&2
    failures=$((failures + 1))
  fi
}

test_command_shims_detect_alternate_optional_modules() {
  local output fake_home
  fake_home=$(mktemp -d)
  output=$(
    HOME=$fake_home
    unset NVM_DIR BUN_INSTALL PNPM_HOME CARGO_HOME GOPATH GO_INSTALL_DIR
    tmux() { :; }
    zellij() { :; }
    docker() { :; }
    gh() { :; }
    gentle-ai() { :; }
    pi() { :; }
    codex() { :; }
    claude() { :; }
    opencode() { :; }
    herdr() { :; }
    lazygit() { :; }
    pnpm() { :; }
    ng() { :; }
    packages_installed() { return 1; }
    npm_global_package_installed() { return 1; }

    audit_module_status tmux
    audit_module_status zellij
    audit_module_status docker
    audit_module_status github-cli
    audit_module_status agent-gentle-ai
    audit_module_status agent-pi
    audit_module_status agent-codex
    audit_module_status agent-claude-code
    audit_module_status agent-opencode
    audit_module_status agent-herdr
    audit_module_status lazygit
    audit_module_status pnpm
    audit_module_status angular-cli
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
    'installed (alternate source)' \
    'installed (alternate source)' \
    'installed (alternate source)' \
    'installed (alternate source)' \
    'installed (alternate source)')" "$output" "command shims identify alternate-source groups and agent CLIs"
  rm -rf "$fake_home"
}

test_group_command_evidence_reports_missing_members() {
  local output
  output=$(
    tmux() { :; }
    packages_installed() { return 1; }
    MODULE_COMMANDS[tmux]='tmux tmux-not-found'
    audit_module_status tmux
  )
  assert_eq 'partial (alternate source; missing commands: tmux-not-found)' "$output" "partial groups name missing command evidence"
}

test_dry_run_execution_skips_alternate_source_modules() {
  local output
  output=$(
    tmux() { :; }
    packages_installed() { return 1; }
    log() { printf '%s\n' "$*"; }
    DRY_RUN=1
    install_module tmux
  )
  assert_contains 'Skipping tmux: installed (alternate source).' "$output" "dry-run execution skips alternate-source modules"
  assert_not_contains 'apt-get install' "$output" "dry-run execution does not plan a reinstall for alternate-source modules"
}

test_live_execution_skips_alternate_source_modules() {
  local output
  output=$(
    tmux() { :; }
    packages_installed() { return 1; }
    apt_install() { printf '%s\n' 'FORBIDDEN: apt install'; }
    log() { printf '%s\n' "$*"; }
    DRY_RUN=0
    install_module tmux
  )
  assert_contains 'Skipping tmux: installed (alternate source).' "$output" "live execution skips alternate-source modules"
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

test_confirm_full_install_does_not_mutate_before_answered() {
  local output rc=0
  output=$({
    # An empty PATH proves no external command runs before the answer.
    # shellcheck disable=SC2123
    PATH=''
    has_readable_tty() { return 0; }
    prompt_full_install_confirmation() { printf 'n'; }
    run_privileged() { printf 'FORBIDDEN: run_privileged called\n'; }
    apt_install() { printf 'FORBIDDEN: apt_install called\n'; }
    log() { :; }
    confirm_full_install || rc=$?
    printf 'CONFIRMED_RC=%s\n' "$rc"
  } 2>&1)
  assert_eq 'CONFIRMED_RC=1' "$output" "declining the single confirmation does not proceed"
  assert_not_contains 'FORBIDDEN' "$output" "the confirmation prompt alone never triggers a privileged or install command"
}

test_confirm_full_install_skips_prompt_with_assume_yes() {
  local output
  output=$({
    ASSUME_YES=1
    NON_INTERACTIVE=0
    prompt_full_install_confirmation() { printf 'FORBIDDEN: prompted despite --yes'; }
    if confirm_full_install; then printf 'CONFIRMED\n'; else printf 'DECLINED\n'; fi
  } 2>&1)
  assert_eq 'CONFIRMED' "$output" "--yes confirms without prompting"
}

test_confirm_full_install_skips_prompt_when_non_interactive() {
  local output
  output=$({
    ASSUME_YES=0
    NON_INTERACTIVE=1
    prompt_full_install_confirmation() { printf 'FORBIDDEN: prompted despite --non-interactive'; }
    if confirm_full_install; then printf 'CONFIRMED\n'; else printf 'DECLINED\n'; fi
  } 2>&1)
  assert_eq 'CONFIRMED' "$output" "--non-interactive confirms without prompting"
}

test_confirm_full_install_default_answer_is_yes() {
  local output
  output=$({
    ASSUME_YES=0
    NON_INTERACTIVE=0
    has_readable_tty() { return 0; }
    prompt_full_install_confirmation() { printf ''; }
    if confirm_full_install; then printf 'CONFIRMED\n'; else printf 'DECLINED\n'; fi
  } 2>&1)
  assert_eq 'CONFIRMED' "$output" "pressing Enter accepts the default yes"
}

test_confirm_full_install_rejects_explicit_no() {
  local output
  output=$({
    ASSUME_YES=0
    NON_INTERACTIVE=0
    has_readable_tty() { return 0; }
    prompt_full_install_confirmation() { printf 'n'; }
    if confirm_full_install; then printf 'CONFIRMED\n'; else printf 'DECLINED\n'; fi
  } 2>&1)
  assert_eq 'DECLINED' "$output" "an explicit no declines the installation"
}

test_confirm_full_install_declines_safely_without_tty() {
  local output
  output=$({
    ASSUME_YES=0
    NON_INTERACTIVE=0
    has_readable_tty() { return 1; }
    prompt_full_install_confirmation() { printf 'FORBIDDEN: prompted without a tty'; }
    if confirm_full_install; then printf 'CONFIRMED\n'; else printf 'DECLINED\n'; fi
  } 2>&1)
  assert_contains 'DECLINED' "$output" "a missing tty declines safely instead of hanging"
  assert_contains '--yes' "$output" "the no-tty fallback explains --yes/--non-interactive"
  assert_not_contains 'FORBIDDEN' "$output" "a missing tty never attempts to read a prompt"
}

test_default_selection_installs_everything() {
  local selected
  selected=$(
    REQUESTED_MODULES=''
    default_selected_modules | tr '\n' ' '
  )
  assert_contains 'cli-modern' "$selected" "the default selection includes optional modules"
  assert_contains 'agent-claude-code' "$selected" "the default selection includes agent modules"
}

test_modules_flag_still_narrows_selection() {
  local selected
  selected=$(
    REQUESTED_MODULES='cli-modern'
    default_selected_modules | tr '\n' ' '
  )
  assert_eq 'cli-modern ' "$selected" "the --modules escape hatch still narrows the plan"
}

test_usage_describes_default_flow() {
  local output
  output=$(usage)
  assert_contains 'single yes/no' "$output" "usage explains the default single-confirmation flow"
  assert_contains '--modules' "$output" "usage still documents the --modules escape hatch"
}

test_dry_run_entrypoint_default_selects_everything() {
  local output
  output=$(bash "$ROOT_DIR/install.sh" --dry-run --non-interactive 2>&1)
  assert_contains 'agent-claude-code' "$output" "the default non-interactive run plans the complete environment"
  assert_contains 'rust' "$output" "the default non-interactive run plans runtime modules too"
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
  # Catalog paths keep $HOME literal; module_installed expands it.
  # shellcheck disable=SC2016
  MODULE_PATH[oh-my-zsh]='$HOME'
  # shellcheck disable=SC2016
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

test_opencode_installed_probe_uses_its_own_binary_path() {
  local fake_home
  fake_home=$(mktemp -d)
  mkdir -p "$fake_home/.opencode/bin"
  printf '#!/bin/sh\necho fake-opencode\n' >"$fake_home/.opencode/bin/opencode"
  chmod +x "$fake_home/.opencode/bin/opencode"

  (
    HOME=$fake_home
    if module_installed agent-opencode; then
      printf '%s\n' 'PASS: opencode is detected as installed from ~/.opencode/bin/opencode'
    else
      printf '%s\n' 'FAIL: opencode is detected as installed from ~/.opencode/bin/opencode' >&2
      exit 1
    fi
  ) || failures=$((failures + 1))

  (
    HOME=$fake_home
    mkdir -p "$HOME/.local/bin"
    printf '#!/bin/sh\necho fake-opencode-wrong-path\n' >"$HOME/.local/bin/opencode"
    chmod +x "$HOME/.local/bin/opencode"
    rm -f "$HOME/.opencode/bin/opencode"
    if module_installed agent-opencode; then
      printf '%s\n' 'FAIL: opencode is not reported installed from the wrong ~/.local/bin path' >&2
      exit 1
    else
      printf '%s\n' 'PASS: opencode is not reported installed from the wrong ~/.local/bin path'
    fi
  ) || failures=$((failures + 1))

  rm -rf "$fake_home"
}

test_execute_plan_isolates_module_failures() {
  local output exitcode=0
  output=$({
    MANDATORY_MODULES=(fake-mandatory-fail fake-mandatory-ok)
    OPTIONAL_MODULES=()
    RESOLVED_MODULES=(fake-mandatory-fail fake-mandatory-ok)
    MODULE_KIND[fake-mandatory-fail]=apt
    MODULE_TITLE[fake-mandatory-fail]='Fake failing module'
    MODULE_PACKAGES[fake-mandatory-fail]='fake-fail-package'
    MODULE_KIND[fake-mandatory-ok]=apt
    MODULE_TITLE[fake-mandatory-ok]='Fake ok module'
    MODULE_PACKAGES[fake-mandatory-ok]='fake-ok-package'
    PRIVILEGES_AVAILABLE=1
    module_install_status() { return 1; }
    apt_update() { return 0; }
    apt_install() {
      if [[ "$*" == *fake-fail-package* ]]; then
        printf 'simulated apt failure\n' >&2
        return 1
      fi
      return 0
    }
    log() { printf '%s\n' "$*" >&2; }

    execute_plan || exitcode=$?
    printf 'EXIT_CODE=%s\n' "$exitcode"
  } 2>&1)
  assert_contains 'Installing fake-mandatory-fail' "$output" "isolation attempts the failing module"
  assert_contains 'Installing fake-mandatory-ok' "$output" "isolation continues to the next module after a failure"
  assert_contains 'Installation report' "$output" "a final status report is always printed"
  assert_contains 'fake-mandatory-fail' "$output" "the report names the failing module"
  assert_contains 'failed' "$output" "the report marks the failing module as failed"
  assert_contains 'ok' "$output" "the report marks the succeeding module as ok"
  assert_contains 'simulated apt failure' "$output" "the report includes a failure reason"
  assert_contains 'EXIT_CODE=1' "$output" "a mandatory module failure yields a non-zero overall exit"
}

test_execute_plan_optional_failure_exits_zero() {
  local output exitcode=0
  output=$({
    MANDATORY_MODULES=()
    OPTIONAL_MODULES=(fake-optional-fail)
    RESOLVED_MODULES=(fake-optional-fail)
    MODULE_KIND[fake-optional-fail]=apt
    MODULE_TITLE[fake-optional-fail]='Fake optional failing module'
    MODULE_PACKAGES[fake-optional-fail]='fake-optional-package'
    PRIVILEGES_AVAILABLE=1
    module_install_status() { return 1; }
    apt_update() { return 0; }
    apt_install() { printf 'simulated optional failure\n' >&2; return 1; }
    log() { printf '%s\n' "$*" >&2; }

    execute_plan || exitcode=$?
    printf 'EXIT_CODE=%s\n' "$exitcode"
  } 2>&1)
  assert_contains 'failed' "$output" "an optional module failure is still reported as failed"
  assert_contains 'EXIT_CODE=0' "$output" "an optional-only failure yields a zero overall exit"
}

test_execute_plan_reports_skipped_and_manual_modules() {
  local output
  output=$(
    MANDATORY_MODULES=(fake-manual)
    OPTIONAL_MODULES=(fake-skipped)
    RESOLVED_MODULES=(fake-manual fake-skipped)
    MODULE_KIND[fake-manual]=guidance
    MODULE_TITLE[fake-manual]='Fake manual guidance'
    MODULE_KIND[fake-skipped]=apt
    MODULE_TITLE[fake-skipped]='Fake already-installed module'
    MODULE_PACKAGES[fake-skipped]='fake-skipped-package'
    PRIVILEGES_AVAILABLE=1
    module_install_status() {
      [[ $1 == fake-skipped ]] && { printf '%s\n' 'installed (managed source)'; return 0; }
      return 1
    }
    log() { printf '%s\n' "$*" >&2; }

    execute_plan || true
  )
  assert_contains 'manual' "$output" "guidance modules are reported as manual"
  assert_contains 'skipped' "$output" "already-installed modules are reported as skipped"
}

# BUG 3: captured module stderr went into the report Detail column verbatim.
# A tool like curl redraws its progress meter in place using carriage
# returns, not newlines, so the whole meter is one giant "line" that blew out
# the fixed-width installation report table.
test_sanitize_module_reason_reduces_progress_meter_noise_to_one_line() {
  local raw sanitized
  raw=$'  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current\r                                 Dload  Upload   Total   Spent    Left  Speed\r100  1256  100  1256    0     0   1256      0  0:00:01 --:--:--  0:00:01  4189\rcurl: (22) The requested URL returned error: 404'
  sanitized=$(sanitize_module_reason "$raw")

  assert_not_contains $'\r' "$sanitized" "sanitized reasons never carry a raw carriage return"
  assert_not_contains 'Dload' "$sanitized" "sanitized reasons drop curl progress-meter noise"
  assert_eq 'curl: (22) The requested URL returned error: 404' "$sanitized" "sanitized reasons keep the last meaningful line"
}

test_sanitize_module_reason_truncates_long_lines() {
  local raw sanitized
  raw=$(printf 'x%.0s' {1..500})
  sanitized=$(sanitize_module_reason "$raw")
  if ((${#sanitized} <= 210)); then
    printf 'PASS: %s\n' 'long reasons are truncated to a sensible width'
  else
    printf 'FAIL: %s\n' 'long reasons are truncated to a sensible width' >&2
    failures=$((failures + 1))
  fi
}

test_run_module_isolated_report_detail_is_readable_after_progress_meter_noise() {
  local output
  output=$({
    RESOLVED_MODULES=(fake-noisy-fail)
    MANDATORY_MODULES=()
    MODULE_KIND[fake-noisy-fail]=apt
    MODULE_TITLE[fake-noisy-fail]='Fake noisy module'
    MODULE_PACKAGES[fake-noisy-fail]='fake-noisy-package'
    PRIVILEGES_AVAILABLE=1
    module_install_status() { return 1; }
    apt_install() {
      printf '  %% Total    %% Received %% Xferd  Average Speed   Time    Time     Time  Current\r                                 Dload  Upload   Total   Spent    Left  Speed\r100  1256  100  1256    0     0   1256      0  0:00:01 --:--:--  0:00:01  4189\rcurl: (22) The requested URL returned error: 404\n' >&2
      return 1
    }
    log() { :; }
    run_module_isolated fake-noisy-fail >/dev/null 2>&1
    printf 'REASON=%s\n' "${MODULE_REASON[fake-noisy-fail]}"
  })
  assert_contains 'REASON=curl: (22) The requested URL returned error: 404' "$output" \
    "the execution report keeps a single readable line after progress-meter noise"
  assert_not_contains 'Dload' "$output" "the execution report drops curl progress-meter noise"
}

test_negotiate_privileges_skips_sudo_when_not_needed() {
  local output
  output=$({
    RESOLVED_MODULES=(bun)
    sudo() { printf 'sudo called: %s\n' "$*"; return 0; }
    negotiate_privileges
    printf 'PRIVILEGES_AVAILABLE=%s\n' "$PRIVILEGES_AVAILABLE"
  } 2>&1)
  assert_not_contains 'sudo called' "$output" "negotiation never calls sudo when no module needs privileges"
  assert_contains 'PRIVILEGES_AVAILABLE=0' "$output" "negotiation reports no privileges needed as unavailable"
}

test_negotiate_privileges_reports_missing_sudo() {
  local output
  output=$({
    RESOLVED_MODULES=(base-packages)
    sudo_available() { return 1; }
    log() { printf '%s\n' "$*" >&2; }
    negotiate_privileges
    printf 'PRIVILEGES_AVAILABLE=%s\n' "$PRIVILEGES_AVAILABLE"
  } 2>&1)
  assert_contains 'sudo is not available' "$output" "negotiation reports clearly when sudo is missing"
  assert_contains 'PRIVILEGES_AVAILABLE=0' "$output" "negotiation without sudo leaves privileges unavailable"
}

test_negotiate_privileges_falls_back_without_tty() {
  local output
  output=$({
    RESOLVED_MODULES=(base-packages)
    has_readable_tty() { return 1; }
    sudo() {
      [[ "$*" == '-n -v' ]] && return 1
      printf 'unexpected sudo call: %s\n' "$*" >&2
      return 2
    }
    log() { printf '%s\n' "$*" >&2; }
    negotiate_privileges
    printf 'PRIVILEGES_AVAILABLE=%s\n' "$PRIVILEGES_AVAILABLE"
  } 2>&1)
  assert_contains 'no privileges' "$output" "negotiation without a tty and without cached sudo reports the failure"
  assert_contains 'PRIVILEGES_AVAILABLE=0' "$output" "negotiation without a tty leaves privileges unavailable"
}

test_negotiate_privileges_acquires_and_releases_keepalive() {
  local pid_before
  pid_before=$(
    RESOLVED_MODULES=(base-packages)
    request_sudo_cached() { return 1; }
    request_sudo_interactively() { return 0; }
    has_readable_tty() { return 0; }
    log() { :; }
    negotiate_privileges
    printf '%s' "$SUDO_KEEPALIVE_PID"
  )
  if [[ -n $pid_before ]] && ! kill -0 "$pid_before" 2>/dev/null; then
    printf '%s\n' 'PASS: the sudo keepalive process is stopped once the negotiation scope ends'
  else
    printf '%s\n' 'FAIL: the sudo keepalive process is stopped once the negotiation scope ends' >&2
    failures=$((failures + 1))
  fi
}

# BUG 1: negotiate_privileges branched on has_readable_tty, which tested
# `[[ -r /dev/tty ]]` — file-permission bits, not whether a controlling
# terminal could actually be opened. Under `curl | bash` with no controlling
# terminal, -r can still report true, so the installer took the interactive
# branch, `sudo -v </dev/tty` failed, and the correct request_sudo_cached
# fallback was never reached. These tests pin the fixed contract: sudo -n -v
# (cached/passwordless, never prompts) is always tried first, and interactive
# prompting is attempted only if that fails and a real tty exists.
test_negotiate_privileges_succeeds_via_cached_sudo_even_when_readable_tty_is_wrong() {
  local output
  output=$({
    RESOLVED_MODULES=(base-packages)
    has_readable_tty() { return 0; }
    request_sudo_interactively() { return 1; }
    request_sudo_cached() { return 0; }
    log() { printf '%s\n' "$*" >&2; }
    negotiate_privileges
    printf 'PRIVILEGES_AVAILABLE=%s\n' "$PRIVILEGES_AVAILABLE"
  } 2>&1)
  assert_contains 'PRIVILEGES_AVAILABLE=1' "$output" \
    "cached/passwordless sudo succeeds privileges even when the tty check would otherwise force the (failing) interactive path"
}

test_negotiate_privileges_never_prompts_interactively_when_cached_sudo_works() {
  local output
  output=$({
    RESOLVED_MODULES=(base-packages)
    has_readable_tty() { return 0; }
    request_sudo_cached() { return 0; }
    request_sudo_interactively() { printf 'FORBIDDEN: interactive sudo prompt attempted\n' >&2; return 1; }
    log() { printf '%s\n' "$*" >&2; }
    negotiate_privileges
    printf 'PRIVILEGES_AVAILABLE=%s\n' "$PRIVILEGES_AVAILABLE"
  } 2>&1)
  assert_not_contains 'FORBIDDEN' "$output" "cached sudo success never triggers an interactive prompt"
  assert_contains 'PRIVILEGES_AVAILABLE=1' "$output" "cached sudo success alone grants privileges"
}

test_negotiate_privileges_prompts_interactively_only_after_cached_sudo_fails_with_a_real_tty() {
  local output
  output=$({
    RESOLVED_MODULES=(base-packages)
    has_readable_tty() { return 0; }
    request_sudo_cached() { return 1; }
    request_sudo_interactively() { printf 'INTERACTIVE_PROMPT_ATTEMPTED\n'; return 0; }
    log() { printf '%s\n' "$*" >&2; }
    negotiate_privileges
    printf 'PRIVILEGES_AVAILABLE=%s\n' "$PRIVILEGES_AVAILABLE"
  } 2>&1)
  assert_contains 'INTERACTIVE_PROMPT_ATTEMPTED' "$output" "interactive sudo is attempted once cached sudo fails and a real tty exists"
  assert_contains 'PRIVILEGES_AVAILABLE=1' "$output" "a successful interactive prompt still grants privileges"
}

test_apt_module_fails_cleanly_without_privileges() {
  local output
  output=$({
    RESOLVED_MODULES=(fake-needs-sudo)
    MANDATORY_MODULES=()
    MODULE_KIND[fake-needs-sudo]=apt
    MODULE_TITLE[fake-needs-sudo]='Fake sudo-needing module'
    MODULE_PACKAGES[fake-needs-sudo]='fake-package'
    PRIVILEGES_AVAILABLE=0
    module_install_status() { return 1; }
    apt_install() { printf 'FORBIDDEN: apt install ran without privileges\n'; return 0; }
    log() { printf '%s\n' "$*" >&2; }
    run_module_isolated fake-needs-sudo
    printf 'RESULT=%s REASON=%s\n' "${MODULE_RESULT[fake-needs-sudo]}" "${MODULE_REASON[fake-needs-sudo]}"
  } 2>&1)
  assert_contains 'RESULT=failed' "$output" "apt modules fail cleanly when privileges were not negotiated"
  assert_contains 'REASON=no privileges' "$output" "apt modules report the no-privileges reason"
  assert_not_contains 'FORBIDDEN' "$output" "apt modules never run apt-get without negotiated privileges"
}

test_catalog_matches_measured_real_sources() {
  assert_eq 'github-release' "${MODULE_KIND[zellij]}" "zellij installs from a GitHub release binary, not apt"
  assert_eq 'go-tarball' "${MODULE_KIND[go]}" "go installs from the official tarball, not apt golang-go"
  assert_eq 'apt' "${MODULE_KIND[tmux]}" "tmux keeps installing from apt"
  assert_eq 'install-script' "${MODULE_KIND[agent-gentle-ai]}" "gentle-ai installs from its own installer, not npm"
  assert_eq 'install-script' "${MODULE_KIND[agent-opencode]}" "opencode installs from its own installer, not npm"
  assert_eq 'install-script' "${MODULE_KIND[agent-claude-code]}" "claude code installs from its own installer, not npm"
  assert_eq 'install-script' "${MODULE_KIND[agent-herdr]}" "herdr installs from its own installer, not npm"
  assert_eq 'npm' "${MODULE_KIND[agent-codex]}" "codex installs from the official @openai/codex npm package"
  assert_eq '@openai/codex' "${MODULE_NPM_PACKAGE[agent-codex]}" "codex's npm package is the official OpenAI one"
  assert_eq 'node-nvm' "${MODULE_DEPS[agent-codex]}" "codex depends on node-nvm like the other npm agent modules"
  assert_eq 'npm' "${MODULE_KIND[agent-pi]}" "pi keeps installing from nvm's global npm"
  assert_eq 'go-install' "${MODULE_KIND[lazygit]}" "lazygit installs via go install"
  assert_eq 'go' "${MODULE_DEPS[lazygit]}" "lazygit depends on the go module"
  assert_eq 'pnpm' "${MODULE_KIND[pnpm]}" "pnpm installs from its own script"
  assert_eq 'npm' "${MODULE_KIND[angular-cli]}" "angular-cli installs via nvm's global npm"
  assert_eq 'node-nvm' "${MODULE_DEPS[angular-cli]}" "angular-cli depends on node-nvm"
  assert_eq 'git-clone' "${MODULE_KIND[zsh-autosuggestions]}" "zsh-autosuggestions is an oh-my-zsh custom plugin clone"
  assert_eq 'git-clone' "${MODULE_KIND[zsh-syntax-highlighting]}" "zsh-syntax-highlighting is an oh-my-zsh custom plugin clone"
  assert_contains '.oh-my-zsh/custom/plugins/zsh-autosuggestions' "${MODULE_PATH[zsh-autosuggestions]}" "zsh-autosuggestions clones into the custom plugins directory"
  assert_contains '.oh-my-zsh/custom/plugins/zsh-syntax-highlighting' "${MODULE_PATH[zsh-syntax-highlighting]}" "zsh-syntax-highlighting clones into the custom plugins directory"
}

test_agent_cli_modules_use_verified_installer_urls() {
  assert_eq 'https://raw.githubusercontent.com/Gentleman-Programming/gentle-ai/main/scripts/install.sh' \
    "${MODULE_URL[agent-gentle-ai]}" "gentle-ai's installer URL is the verified GitHub-hosted script"
  assert_eq 'https://claude.ai/install.sh' \
    "${MODULE_URL[agent-claude-code]}" "claude code's installer URL is the verified claude.ai script"
  assert_eq 'https://opencode.ai/install' \
    "${MODULE_URL[agent-opencode]}" "opencode's installer URL is the verified opencode.ai script"
  assert_eq 'https://herdr.dev/install.sh' \
    "${MODULE_URL[agent-herdr]}" "herdr's installer URL is the verified herdr.dev script"

  assert_not_contains 'TODO-verify.invalid' "${MODULE_URL[agent-gentle-ai]}${MODULE_URL[agent-claude-code]}${MODULE_URL[agent-opencode]}${MODULE_URL[agent-herdr]}" \
    "no install-script module keeps a placeholder installer URL"

  assert_eq 'bash' "${MODULE_INTERPRETER[agent-gentle-ai]:-bash}" "gentle-ai's installer runs under bash"
  assert_eq 'bash' "${MODULE_INTERPRETER[agent-claude-code]:-bash}" "claude code's installer runs under bash"
  assert_eq 'bash' "${MODULE_INTERPRETER[agent-opencode]:-bash}" "opencode's installer runs under bash"
  assert_eq 'sh' "${MODULE_INTERPRETER[agent-herdr]:-bash}" "herdr's installer runs under sh, as its README documents"
}

test_install_script_modules_pipe_to_their_interpreter() {
  local module interpreter output
  for module in agent-gentle-ai agent-claude-code agent-opencode; do
    interpreter=${MODULE_INTERPRETER[$module]:-bash}
    output=$({
      run_remote_script() { printf 'RAN url=%s interpreter=%s\n' "$1" "$2"; return 0; }
      perform_module_install "$module" install-script
      printf 'EXIT=%s\n' $?
    } 2>&1)
    assert_contains "RAN url=${MODULE_URL[$module]} interpreter=$interpreter" "$output" \
      "$module pipes its verified installer URL through run_remote_script with $interpreter"
    assert_contains 'EXIT=0' "$output" "$module's install-script kind succeeds when run_remote_script succeeds"
  done

  output=$({
    run_remote_script() { printf 'RAN url=%s interpreter=%s\n' "$1" "$2"; return 0; }
    perform_module_install agent-herdr install-script
    printf 'EXIT=%s\n' $?
  } 2>&1)
  assert_contains "RAN url=${MODULE_URL[agent-herdr]} interpreter=sh" "$output" \
    "herdr pipes its verified installer URL through run_remote_script with sh"
  assert_contains 'EXIT=0' "$output" "herdr's install-script kind succeeds when run_remote_script succeeds"
}

test_agent_codex_dry_run_plan_installs_via_npm() {
  local plan
  plan=$(module_plan_lines agent-codex)
  assert_contains 'npm install -g @openai/codex' "$plan" "codex's dry-run plan installs the official npm package"
  assert_not_contains 'MANUAL STEP REQUIRED' "$plan" "codex's dry-run plan no longer refuses as a manual step"
}

test_install_script_dry_run_plan_prints_the_real_command() {
  local module plan
  for module in agent-gentle-ai agent-claude-code agent-opencode; do
    plan=$(module_plan_lines "$module")
    assert_contains "${MODULE_URL[$module]}" "$plan" "$module's dry-run plan shows its real installer URL"
    assert_contains '| bash' "$plan" "$module's dry-run plan pipes into bash"
    assert_not_contains 'MANUAL STEP REQUIRED' "$plan" "$module's dry-run plan no longer refuses as a manual step"
  done

  plan=$(module_plan_lines agent-herdr)
  assert_contains "${MODULE_URL[agent-herdr]}" "$plan" "herdr's dry-run plan shows its real installer URL"
  assert_contains '| sh' "$plan" "herdr's dry-run plan pipes into sh, matching its documented install"
  assert_not_contains 'MANUAL STEP REQUIRED' "$plan" "herdr's dry-run plan no longer refuses as a manual step"
}

test_npm_module_survives_missing_nvm_when_npm_exists_elsewhere() {
  local output
  output=$({
    npm_provider_is_nvm() { return 1; }
    source_nvm() { printf 'FORBIDDEN: source_nvm called\n' >&2; return 1; }
    npm() { printf 'npm install -g %s\n' "$*"; return 0; }
    command() {
      if [[ $1 == -v && $2 == npm ]]; then return 0; fi
      builtin command "$@"
    }
    perform_module_install agent-pi npm
    printf 'EXIT=%s\n' $?
  } 2>&1)
  assert_contains 'EXIT=0' "$output" "an npm module succeeds using whatever npm is already on PATH"
  assert_not_contains 'FORBIDDEN' "$output" "an npm module never sources nvm when nvm is not the npm provider"
}

test_npm_module_fails_cleanly_with_no_npm_anywhere() {
  local output
  output=$({
    npm_provider_is_nvm() { return 1; }
    command() {
      if [[ $1 == -v && $2 == npm ]]; then return 1; fi
      builtin command "$@"
    }
    perform_module_install agent-pi npm
    printf 'EXIT=%s\n' $?
  } 2>&1)
  assert_contains 'npm is not available' "$output" "an npm module reports clearly when no npm is available at all"
  assert_contains 'EXIT=1' "$output" "an npm module fails cleanly instead of aborting the run when npm is missing"
}

test_github_release_binary_installs_from_archive() {
  local fake_home archive_dir output
  fake_home=$(mktemp -d)
  archive_dir=$(mktemp -d)
  mkdir -p "$archive_dir/payload"
  printf '#!/bin/sh\necho fake-zellij\n' >"$archive_dir/payload/zellij"
  chmod +x "$archive_dir/payload/zellij"
  (cd "$archive_dir/payload" && tar -czf "$archive_dir/zellij.tar.gz" zellij)

  output=$({
    HOME=$fake_home
    curl() {
      local dest=''
      while (($#)); do
        case $1 in
          -o) dest=$2; shift 2 ;;
          *) shift ;;
        esac
      done
      cp "$archive_dir/zellij.tar.gz" "$dest"
    }
    perform_module_install zellij github-release
    printf 'EXIT=%s\n' $?
  } 2>&1)

  assert_contains 'EXIT=0' "$output" "the github-release installer succeeds when the archive contains the binary"
  if [[ -x "$fake_home/.local/bin/zellij" ]]; then
    printf '%s\n' 'PASS: the github-release installer places an executable binary in ~/.local/bin'
  else
    printf '%s\n' 'FAIL: the github-release installer places an executable binary in ~/.local/bin' >&2
    failures=$((failures + 1))
  fi

  rm -rf "$fake_home" "$archive_dir"
}

test_go_tarball_installs_into_local_go() {
  local fake_home archive_dir output
  fake_home=$(mktemp -d)
  archive_dir=$(mktemp -d)
  mkdir -p "$archive_dir/payload/go/bin"
  printf '#!/bin/sh\necho fake-go\n' >"$archive_dir/payload/go/bin/go"
  chmod +x "$archive_dir/payload/go/bin/go"
  (cd "$archive_dir/payload" && tar -czf "$archive_dir/go.tar.gz" go)

  output=$({
    HOME=$fake_home
    curl() {
      local dest=''
      while (($#)); do
        case $1 in
          -o) dest=$2; shift 2 ;;
          *) shift ;;
        esac
      done
      cp "$archive_dir/go.tar.gz" "$dest"
    }
    perform_module_install go go-tarball
    printf 'EXIT=%s\n' $?
  } 2>&1)

  assert_contains 'EXIT=0' "$output" "the go tarball installer succeeds"
  if [[ -x "$fake_home/.local/go/bin/go" ]]; then
    printf '%s\n' 'PASS: the go tarball installer extracts into ~/.local/go'
  else
    printf '%s\n' 'FAIL: the go tarball installer extracts into ~/.local/go' >&2
    failures=$((failures + 1))
  fi

  rm -rf "$fake_home" "$archive_dir"
}

test_go_install_binary_invokes_local_go_toolchain() {
  local fake_home output
  fake_home=$(mktemp -d)
  mkdir -p "$fake_home/.local/go/bin"
  cat >"$fake_home/.local/go/bin/go" <<'EOF'
#!/bin/sh
printf 'go %s\n' "$*"
EOF
  chmod +x "$fake_home/.local/go/bin/go"

  output=$({
    HOME=$fake_home
    perform_module_install lazygit go-install
    printf 'EXIT=%s\n' $?
  } 2>&1)

  assert_contains 'go install github.com/jesseduffield/lazygit@latest' "$output" "the go-install kind runs go install with the module's package"
  assert_contains 'EXIT=0' "$output" "the go-install kind succeeds when the go toolchain is present"

  rm -rf "$fake_home"
}

test_go_install_binary_fails_cleanly_without_go_toolchain() {
  local fake_home output
  fake_home=$(mktemp -d)

  output=$({
    HOME=$fake_home
    perform_module_install lazygit go-install
    printf 'EXIT=%s\n' $?
  } 2>&1)

  assert_contains 'Go toolchain not found' "$output" "the go-install kind reports clearly when go is not installed yet"
  assert_contains 'EXIT=1' "$output" "the go-install kind fails cleanly instead of crashing without the go toolchain"

  rm -rf "$fake_home"
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
test_confirm_full_install_does_not_mutate_before_answered
test_confirm_full_install_skips_prompt_with_assume_yes
test_confirm_full_install_skips_prompt_when_non_interactive
test_confirm_full_install_default_answer_is_yes
test_confirm_full_install_rejects_explicit_no
test_confirm_full_install_declines_safely_without_tty
test_default_selection_installs_everything
test_modules_flag_still_narrows_selection
test_usage_describes_default_flow
test_dry_run_entrypoint_default_selects_everything
test_dangling_zsh_config_paths_are_guarded
test_module_path_probe_uses_catalog_metadata
test_execute_plan_isolates_module_failures
test_execute_plan_optional_failure_exits_zero
test_execute_plan_reports_skipped_and_manual_modules
test_sanitize_module_reason_reduces_progress_meter_noise_to_one_line
test_sanitize_module_reason_truncates_long_lines
test_run_module_isolated_report_detail_is_readable_after_progress_meter_noise
test_negotiate_privileges_skips_sudo_when_not_needed
test_negotiate_privileges_reports_missing_sudo
test_negotiate_privileges_falls_back_without_tty
test_negotiate_privileges_acquires_and_releases_keepalive
test_negotiate_privileges_succeeds_via_cached_sudo_even_when_readable_tty_is_wrong
test_negotiate_privileges_never_prompts_interactively_when_cached_sudo_works
test_negotiate_privileges_prompts_interactively_only_after_cached_sudo_fails_with_a_real_tty
test_apt_module_fails_cleanly_without_privileges
test_catalog_matches_measured_real_sources
test_agent_cli_modules_use_verified_installer_urls
test_oh_my_zsh_pins_its_install_directory() {
  # Every oh-my-zsh user exports ZSH from their own .zshrc, so the variable is
  # present in the environment that launches this installer. If the module does
  # not pin it, the upstream installer targets the inherited directory, refuses
  # to install, and fails a mandatory module.
  local output fake_home
  fake_home=$(mktemp -d)

  output=$({
    HOME=$fake_home
    # Simulates a ZSH value inherited from the caller, which must be ignored.
    # shellcheck disable=SC2034
    ZSH=/somewhere/else/.oh-my-zsh
    run_remote_script() { printf 'RAN %s\n' "$*"; return 0; }
    perform_module_install oh-my-zsh oh-my-zsh
  } 2>&1)

  assert_contains "ZSH=$fake_home/.oh-my-zsh" "$output" \
    "oh-my-zsh pins ZSH to the running user's home instead of inheriting it"
  rm -rf "$fake_home"
}

test_install_script_modules_pipe_to_their_interpreter
test_oh_my_zsh_pins_its_install_directory
# R2 / R3-template-guard-counter: the guard's negative control incremented an
# upper-case counter the suite never reads, so it could print FAIL and still
# let the suite exit 0. A check that cannot fail the suite is not a check.
test_every_failure_branch_uses_the_suite_counter() {
  local stray
  # The class bracket keeps this pattern from matching its own source line.
  stray=$(grep -nE 'FAILURE[S]=' "$ROOT_DIR/tests/test_bootstrap.sh" || true)
  assert_eq '' "$stray" "no failure branch increments a counter the suite never reads"
}

# Found by a clean full install in a container: rust was the only module that
# failed, with `curl: (23) Failure writing output to destination`. Root cause is
# a contract bug, not the network: run_remote_script could only forward ENV
# assignments, so rustup's interpreter arguments (`-s -- -y`) were handed to
# `env`, which died with "invalid option -- 's'" and closed the pipe.
test_run_remote_script_separates_env_from_interpreter_arguments() {
  local output
  output=$({
    curl() { printf 'script-body\n'; }
    env() { printf 'ENV_ARGS:%s\n' "$*"; }
    run_remote_script https://example.invalid/x sh -- -s -- -y
  } 2>&1)

  assert_contains 'ENV_ARGS:sh -s -- -y' "$output" \
    "interpreter arguments reach the interpreter instead of being parsed as env assignments"
  assert_not_contains 'ENV_ARGS:-s' "$output" \
    "interpreter arguments are never passed to env as assignments"
}

test_run_remote_script_still_forwards_env_assignments() {
  local output
  output=$({
    curl() { printf 'script-body\n'; }
    env() { printf 'ENV_ARGS:%s\n' "$*"; }
    run_remote_script https://example.invalid/x bash KEEP_ZSHRC=yes RUNZSH=no
  } 2>&1)

  assert_contains 'ENV_ARGS:KEEP_ZSHRC=yes RUNZSH=no bash' "$output" \
    "env assignments still reach env, ahead of the interpreter"
}

test_rust_module_invokes_its_interpreter_with_unattended_flags() {
  local output
  output=$({
    run_remote_script() { printf 'CALL:%s\n' "$*"; }
    perform_module_install rust rustup
  } 2>&1)

  assert_contains -- "$output" "the rust module passes a separator so its flags are interpreter arguments"
  assert_contains '-s' "$output" "the rust module keeps rustup's unattended flags"
  assert_contains '-y' "$output" "the rust module keeps rustup's -y flag"
}

# Found by running the installer in a real throwaway WSL distribution: after
# spidy-config had just replaced ~/.zshrc (with a backup), the run still printed
# "Preserving existing ~/.zshrc; no shell configuration was overwritten" and
# advised setting ZSH_THEME by hand — which the shipped file already sets.
# configure_zsh predates spidy-config and now only emits contradictions.
test_execute_plan_does_not_claim_to_preserve_a_replaced_zshrc() {
  local fake_home output
  fake_home=$(mktemp -d)
  printf 'pre-existing\n' >"$fake_home/.zshrc"

  output=$({
    HOME=$fake_home
    RESOLVED_MODULES=()
    execute_plan
  } 2>&1)

  assert_not_contains 'no shell configuration was overwritten' "$output" \
    "the run never claims it preserved a shell configuration that spidy-config owns"
  assert_not_contains 'set ZSH_THEME' "$output" \
    "the run never tells the user to set a theme the shipped zshrc already sets"
  rm -rf "$fake_home"
}

test_every_failure_branch_uses_the_suite_counter
test_execute_plan_does_not_claim_to_preserve_a_replaced_zshrc
test_run_remote_script_separates_env_from_interpreter_arguments
test_run_remote_script_still_forwards_env_assignments
test_rust_module_invokes_its_interpreter_with_unattended_flags
test_agent_codex_dry_run_plan_installs_via_npm
test_install_script_dry_run_plan_prints_the_real_command
test_opencode_installed_probe_uses_its_own_binary_path
test_npm_module_survives_missing_nvm_when_npm_exists_elsewhere
test_npm_module_fails_cleanly_with_no_npm_anywhere
test_github_release_binary_installs_from_archive
test_go_tarball_installs_into_local_go
test_go_install_binary_invokes_local_go_toolchain
test_go_install_binary_fails_cleanly_without_go_toolchain

test_bootstrap_rejects_non_ubuntu_host() {
  local fake_os_release output rc=0
  fake_os_release=$(mktemp)
  cat >"$fake_os_release" <<'EOF'
ID=fedora
VERSION_ID=39
EOF

  output=$({
    BOOTSTRAP_OS_RELEASE_FILE=$fake_os_release
    uname() { printf 'Linux\n'; }
    bootstrap_validate_host
  } 2>&1) && rc=$? || rc=$?

  assert_contains 'Unsupported host: detected fedora 39' "$output" "bootstrap.sh rejects a non-Ubuntu-24.04 host with a clear message"
  assert_eq '1' "$rc" "bootstrap.sh's host check exits non-zero on an unsupported host"
  rm -f "$fake_os_release"
}

test_bootstrap_accepts_ubuntu_2404_host() {
  local fake_os_release rc=0
  fake_os_release=$(mktemp)
  cat >"$fake_os_release" <<'EOF'
ID=ubuntu
VERSION_ID=24.04
EOF

  (
    BOOTSTRAP_OS_RELEASE_FILE=$fake_os_release
    uname() { printf 'Linux\n'; }
    bootstrap_validate_host
  ) && rc=$? || rc=$?

  assert_eq '0' "$rc" "bootstrap.sh accepts a real Ubuntu 24.04 host"
  rm -f "$fake_os_release"
}

test_bootstrap_ensure_git_curl_installs_git_via_apt_when_missing() {
  local output
  output=$({
    command() {
      case "$1 $2" in
        '-v curl') return 0 ;;
        '-v git') return 1 ;;
        '-v sudo') return 0 ;;
        *) builtin command "$@" ;;
      esac
    }
    bootstrap_apt_install_git() { printf 'APT_INSTALL_GIT_CALLED\n'; return 0; }
    bootstrap_ensure_git_curl
    printf 'EXIT=%s\n' $?
  } 2>&1)

  assert_contains 'APT_INSTALL_GIT_CALLED' "$output" "bootstrap.sh installs git via apt when it is missing"
  assert_contains 'EXIT=0' "$output" "bootstrap.sh succeeds once git is installed"
}

test_bootstrap_ensure_git_curl_fails_cleanly_without_sudo() {
  local output
  output=$({
    command() {
      case "$1 $2" in
        '-v curl') return 0 ;;
        '-v git') return 1 ;;
        '-v sudo') return 1 ;;
        *) builtin command "$@" ;;
      esac
    }
    bootstrap_ensure_git_curl
    printf 'EXIT=%s\n' $?
  } 2>&1)

  assert_contains 'sudo is unavailable' "$output" "bootstrap.sh reports clearly when git is missing and sudo is unavailable"
  assert_contains 'EXIT=1' "$output" "bootstrap.sh fails cleanly instead of aborting when git cannot be installed"
}

test_bootstrap_ensure_git_curl_fails_without_curl() {
  local output
  output=$({
    command() {
      case "$1 $2" in
        '-v curl') return 1 ;;
        *) builtin command "$@" ;;
      esac
    }
    bootstrap_ensure_git_curl
    printf 'EXIT=%s\n' $?
  } 2>&1)

  assert_contains 'curl is required' "$output" "bootstrap.sh reports clearly when curl is missing"
  assert_contains 'EXIT=1' "$output" "bootstrap.sh fails cleanly when curl is missing"
}

test_bootstrap_checkout_dir_derives_from_home() {
  local fake_home resolved
  fake_home=$(mktemp -d)
  resolved=$(HOME=$fake_home XDG_DATA_HOME='' bootstrap_checkout_dir)
  assert_eq "$fake_home/.local/share/spidy-environment" "$resolved" "the checkout directory derives from \$HOME, never a hardcoded path"
  rm -rf "$fake_home"
}

test_bootstrap_ensure_checkout_clones_when_absent() {
  local fake_home output
  fake_home=$(mktemp -d)

  output=$({
    HOME=$fake_home
    git() {
      if [[ $1 == clone ]]; then
        printf 'GIT_CLONE %s %s\n' "$2" "$3"
        mkdir -p "$3/.git"
        return 0
      fi
      printf 'UNEXPECTED_GIT_CALL %s\n' "$*" >&2
      return 1
    }
    bootstrap_ensure_checkout
    printf 'EXIT=%s\n' $?
  } 2>&1)

  assert_contains "GIT_CLONE $BOOTSTRAP_REPO_URL $fake_home/.local/share/spidy-environment" "$output" "a missing checkout is cloned from the real repository URL into \$XDG_DATA_HOME/spidy-environment"
  assert_contains 'EXIT=0' "$output" "cloning a missing checkout succeeds"
  rm -rf "$fake_home"
}

test_bootstrap_ensure_checkout_pulls_when_present() {
  local fake_home checkout_dir output
  fake_home=$(mktemp -d)
  checkout_dir="$fake_home/.local/share/spidy-environment"
  mkdir -p "$checkout_dir/.git"

  output=$({
    HOME=$fake_home
    git() {
      if [[ $1 == -C && $3 == pull && $4 == --ff-only ]]; then
        printf 'GIT_PULL %s\n' "$2"
        return 0
      fi
      printf 'UNEXPECTED_GIT_CALL %s\n' "$*" >&2
      return 1
    }
    bootstrap_ensure_checkout
    printf 'EXIT=%s\n' $?
  } 2>&1)

  assert_contains "GIT_PULL $checkout_dir" "$output" "an existing checkout is fast-forwarded instead of re-cloned"
  assert_contains 'EXIT=0' "$output" "updating an existing checkout succeeds"
  rm -rf "$fake_home"
}

test_bootstrap_launcher_execs_checkout_install() {
  local fake_home checkout_dir launcher_path output
  fake_home=$(mktemp -d)
  checkout_dir="$fake_home/.local/share/spidy-environment"
  mkdir -p "$checkout_dir"
  cat >"$checkout_dir/install.sh" <<'EOF'
#!/usr/bin/env bash
printf 'install.sh called with: %s\n' "$*"
EOF
  chmod +x "$checkout_dir/install.sh"

  (
    HOME=$fake_home
    bootstrap_install_launcher
  ) >/dev/null 2>&1

  launcher_path="$fake_home/.local/bin/spidy-environment"
  if [[ -x "$launcher_path" ]]; then
    printf '%s\n' 'PASS: the launcher is installed and executable'
  else
    printf '%s\n' 'FAIL: the launcher is installed and executable' >&2
    failures=$((failures + 1))
  fi

  assert_contains "exec \"$checkout_dir/install.sh\"" "$(cat "$launcher_path")" "the launcher execs the checkout's install.sh, resolved at install time"

  output=$("$launcher_path" --dry-run --modules foo 2>&1)
  assert_eq 'install.sh called with: --dry-run --modules foo' "$output" "the launcher forwards all arguments to the checkout's install.sh"
  rm -rf "$fake_home"
}

test_bootstrap_ensure_path_appends_when_missing() {
  local fake_home output
  fake_home=$(mktemp -d)

  output=$({
    HOME=$fake_home
    SHELL='/bin/bash'
    PATH='/usr/bin:/bin'
    bootstrap_ensure_path
    printf 'EXIT=%s\n' $?
    bootstrap_ensure_path
  } 2>&1)

  assert_contains 'Added ~/.local/bin to PATH' "$output" "a missing ~/.local/bin on PATH is reported and fixed"
  assert_contains 'EXIT=0' "$output" "ensuring PATH succeeds"
  local occurrences
  # The pattern matches the literal line, so nothing may expand here.
  # shellcheck disable=SC2016
  occurrences=$(grep -c 'export PATH="\$HOME/.local/bin:\$PATH"' "$fake_home/.bashrc")
  assert_eq '1' "$occurrences" "the PATH export line is added exactly once, even across repeated runs"
  rm -rf "$fake_home"
}

test_bootstrap_ensure_path_skips_when_present() {
  local fake_home output
  fake_home=$(mktemp -d)

  output=$({
    HOME=$fake_home
    SHELL='/bin/bash'
    PATH="$fake_home/.local/bin:/usr/bin:/bin"
    bootstrap_ensure_path
    printf 'EXIT=%s\n' $?
  } 2>&1)

  assert_contains 'EXIT=0' "$output" "ensuring PATH is a no-op when already present"
  if [[ -f "$fake_home/.bashrc" ]]; then
    printf '%s\n' 'FAIL: no rc file is touched when ~/.local/bin is already on PATH' >&2
    failures=$((failures + 1))
  else
    printf '%s\n' 'PASS: no rc file is touched when ~/.local/bin is already on PATH'
  fi
  rm -rf "$fake_home"
}

test_config_install_file_backs_up_existing_destination() {
  local fake_home dest backups
  fake_home=$(mktemp -d)
  dest="$fake_home/.zshrc"
  printf 'PRE-EXISTING USER CONTENT\n' >"$dest"

  (
    HOME=$fake_home
    log() { :; }
    config_install_file "$ROOT_DIR/config/zsh/zshrc" "$dest"
  )

  mapfile -t backups < <(find "$fake_home" -maxdepth 1 -name '.zshrc.bak.*')
  assert_eq '1' "${#backups[@]}" "exactly one backup is created for a pre-existing destination"
  assert_contains 'PRE-EXISTING USER CONTENT' "$(cat "${backups[0]}" 2>/dev/null)" "the backup preserves the original content instead of clobbering it"
  assert_not_contains 'PRE-EXISTING USER CONTENT' "$(cat "$dest")" "the destination itself now holds the installed config, not the old content"
  rm -rf "$fake_home"
}

test_config_install_file_does_not_back_up_a_missing_destination() {
  local fake_home dest backups
  fake_home=$(mktemp -d)
  dest="$fake_home/.zshrc"

  (
    HOME=$fake_home
    log() { :; }
    config_install_file "$ROOT_DIR/config/zsh/zshrc" "$dest"
  )

  mapfile -t backups < <(find "$fake_home" -maxdepth 1 -name '.zshrc.bak.*')
  assert_eq '0' "${#backups[@]}" "no backup is created when there is nothing to preserve"
  if [[ -f $dest ]]; then
    printf '%s\n' 'PASS: the destination is installed when previously absent'
  else
    printf '%s\n' 'FAIL: the destination is installed when previously absent' >&2
    failures=$((failures + 1))
  fi
  rm -rf "$fake_home"
}

test_config_install_file_substitutes_home_marker() {
  local fake_home source dest content
  fake_home=$(mktemp -d)
  source=$(mktemp)
  printf 'command: __SPIDY_HOME__/.local/bin/engram\n' >"$source"
  dest="$fake_home/marker-target"

  (
    HOME=$fake_home
    log() { :; }
    config_install_file "$source" "$dest"
  )

  content=$(cat "$dest")
  assert_not_contains '__SPIDY_HOME__' "$content" "the marker is fully substituted"
  assert_contains "$fake_home/.local/bin/engram" "$content" "the marker is replaced with the real \$HOME"
  rm -rf "$fake_home" "$source"
}

test_config_install_all_leaves_zero_markers() {
  local fake_home hits
  fake_home=$(mktemp -d)

  (
    HOME=$fake_home
    log() { :; }
    config_install_all
  )

  hits=$(grep -rl '__SPIDY_HOME__' "$fake_home" 2>/dev/null | wc -l) || true
  assert_eq '0' "$hits" "no installed file still carries the __SPIDY_HOME__ marker"
  rm -rf "$fake_home"
}

test_config_install_all_places_expected_destinations() {
  local fake_home
  fake_home=$(mktemp -d)

  (
    HOME=$fake_home
    log() { :; }
    config_install_all
  )

  local expected=(
    ".zshrc"
    ".p10k.zsh"
    ".config/zellij/config.kdl"
    ".config/herdr/config.toml"
  )
  local path all_present=1
  for path in "${expected[@]}"; do
    if [[ ! -e "$fake_home/$path" ]]; then
      printf 'FAIL: expected config destination missing: %s\n' "$path" >&2
      failures=$((failures + 1))
      all_present=0
    fi
  done
  ((all_present)) && printf '%s\n' 'PASS: every mapped config destination is installed'

  # Agent configuration comes from gentle-ai, never from this tree.
  for path in .claude .codex .config/opencode .pi; do
    if [[ -e "$fake_home/$path" ]]; then
      printf 'FAIL: the config tree installs no agent configuration (%s)\n' "$path" >&2
      failures=$((failures + 1))
    else
      printf 'PASS: the config tree installs no agent configuration (%s)\n' "$path"
    fi
  done
  rm -rf "$fake_home"
}

test_config_module_is_wired_into_the_catalog() {
  assert_eq 'config-tree' "${MODULE_KIND[spidy-config]}" "spidy-config is registered as a config-tree module"
  assert_contains 'spidy-config' "${OPTIONAL_MODULES[*]}" "spidy-config is selectable as an optional module"

  resolve_modules spidy-config
  assert_contains 'spidy-config' "${RESOLVED_MODULES[*]}" "spidy-config resolves when requested"

  local plan
  plan=$(module_plan_lines spidy-config)
  assert_contains 'spidy-config' "$plan" "spidy-config prints a dry-run plan line"
}

test_config_module_dry_run_entrypoint_includes_it() {
  local output
  output=$(bash "$ROOT_DIR/install.sh" --dry-run --non-interactive --modules spidy-config 2>&1)
  assert_contains 'spidy-config' "$output" "the dry-run entrypoint plans the config module when requested"
}

test_config_module_execution_reports_ok() {
  local fake_home output
  fake_home=$(mktemp -d)

  output=$(
    HOME=$fake_home
    PRIVILEGES_AVAILABLE=1
    resolve_modules spidy-config
    run_module_isolated spidy-config
    printf 'RESULT=%s\n' "${MODULE_RESULT[spidy-config]}"
  )

  assert_contains 'RESULT=ok' "$output" "the isolated executor reports the config module as ok"
  rm -rf "$fake_home"
}

# The owner's decision: gentle-ai only needs to be downloaded (agent-gentle-ai
# stays). The installer's responsibility for gentle-ai stops there; the user
# runs `gentle-ai` themselves afterwards and configures it through its own
# interface. This pins the removed state: no gentle-ai-config module, no
# GENTLE_AI_CONFIG_* selection, and no automatic `review mode enable`.
test_gentle_ai_config_module_is_removed_from_the_catalog() {
  if module_exists gentle-ai-config; then
    printf 'FAIL: %s\n' "gentle-ai-config is no longer a catalog module" >&2
    failures=$((failures + 1))
  else
    printf 'PASS: %s\n' "gentle-ai-config is no longer a catalog module"
  fi

  assert_not_contains 'gentle-ai-config' "${MODULE_IDS[*]}" "gentle-ai-config is not in MODULE_IDS"
  assert_not_contains 'gentle-ai-config' "${OPTIONAL_MODULES[*]}" "gentle-ai-config is not in OPTIONAL_MODULES"

  local plan
  plan=$(bash "$ROOT_DIR/install.sh" --dry-run --non-interactive --modules all 2>&1)
  assert_not_contains 'gentle-ai-config' "$plan" "the resolved --modules all plan no longer includes gentle-ai-config"
  assert_not_contains 'review mode enable' "$plan" "the resolved --modules all plan no longer enables receipt-driven development automatically"
  assert_contains 'agent-gentle-ai' "$plan" "the resolved --modules all plan still installs the gentle-ai CLI itself"

  if declare -f perform_gentle_ai_config_install >/dev/null 2>&1; then
    printf 'FAIL: %s\n' "perform_gentle_ai_config_install no longer exists" >&2
    failures=$((failures + 1))
  else
    printf 'PASS: %s\n' "perform_gentle_ai_config_install no longer exists"
  fi
}

test_module_panel_lists_every_resolved_module_exactly_once() {
  resolve_modules "${OPTIONAL_MODULES[@]}"
  local output module occurrences
  output=$(render_module_panel)
  for module in "${RESOLVED_MODULES[@]}"; do
    occurrences=$(count_module_title_lines "${MODULE_TITLE[$module]}" "$output")
    assert_eq "1" "$occurrences" "the panel lists '$module' exactly once"
  done
}

test_module_panel_shows_overall_total() {
  resolve_modules "${OPTIONAL_MODULES[@]}"
  local output
  output=$(render_module_panel)
  assert_contains "Total modules: ${#RESOLVED_MODULES[@]}" "$output" "the panel states the overall total module count"
}

test_module_panel_uses_fallback_group_for_a_module_without_a_configured_group() {
  local saved_group=${MODULE_GROUP[github-cli]-}
  unset 'MODULE_GROUP[github-cli]'
  resolve_modules github-cli
  local output
  output=$(render_module_panel)
  assert_contains "$UI_FALLBACK_GROUP" "$output" "a module with no MODULE_GROUP entry falls back to the default group"
  assert_eq "1" "$(count_module_title_lines "${MODULE_TITLE[github-cli]}" "$output")" \
    "the fallback-grouped module still appears in the panel instead of being dropped"
  MODULE_GROUP[github-cli]=$saved_group
}

test_module_panel_group_counts_match_listed_modules() {
  resolve_modules "${OPTIONAL_MODULES[@]}"
  local output line group="" declared=0 count=0 mismatches=""
  output=$(render_module_panel)
  while IFS= read -r line; do
    if [[ "$line" =~ ^([A-Za-z][A-Za-z0-9\ /()-]*)\ \(([0-9]+)\)$ ]]; then
      if [[ -n "$group" && "$count" -ne "$declared" ]]; then
        mismatches+="$group:declared=$declared:actual=$count;"
      fi
      group=${BASH_REMATCH[1]}
      declared=${BASH_REMATCH[2]}
      count=0
    elif [[ "$line" == '  - '* ]]; then
      count=$((count + 1))
    fi
  done <<<"$output"
  if [[ -n "$group" && "$count" -ne "$declared" ]]; then
    mismatches+="$group:declared=$declared:actual=$count;"
  fi
  assert_eq "" "$mismatches" "every group heading's declared count matches the number of modules listed under it"
}

test_module_panel_marks_mandatory_modules() {
  resolve_modules "${OPTIONAL_MODULES[@]}"
  local output module
  output=$(render_module_panel)
  for module in "${MANDATORY_MODULES[@]}"; do
    assert_contains "${MODULE_TITLE[$module]} (mandatory)" "$output" "mandatory module '$module' is marked (mandatory) in the panel"
  done
  assert_not_contains "${MODULE_TITLE[cli-modern]} (mandatory)" "$output" "a non-mandatory module is not marked (mandatory)"
}

test_module_panel_plain_mode_has_no_ansi_escapes_when_no_color_is_set() {
  resolve_modules "${OPTIONAL_MODULES[@]}"
  local output
  output=$(NO_COLOR=1 render_module_panel)
  assert_not_contains $'\e[' "$output" "NO_COLOR disables ANSI escape sequences in the panel"
  assert_contains "${MODULE_TITLE[base-packages]}" "$output" "the plain-mode panel still contains real module content"
}

test_module_panel_plain_mode_has_no_ansi_escapes_on_a_dumb_terminal() {
  resolve_modules "${OPTIONAL_MODULES[@]}"
  local output
  output=$(TERM=dumb render_module_panel)
  assert_not_contains $'\e[' "$output" "TERM=dumb disables ANSI escape sequences in the panel"
}

test_install_entrypoint_renders_grouped_panel() {
  local output
  output=$(bash "$ROOT_DIR/install.sh" --dry-run --non-interactive --modules all 2>&1)
  assert_contains 'Installation summary' "$output" "the install entrypoint still prints the summary heading"
  assert_contains 'Mandatory baseline (5)' "$output" "the install entrypoint groups mandatory modules under their catalog group with a count"
  assert_contains 'Authentication, API keys, provider login, and SSH keys are manual' "$output" \
    "the install entrypoint keeps the manual-steps notice"
}

# Regression test for a broken box: on a real pty, long titles plus the old
# verbose "— installed (managed source), will be skipped" suffix pushed
# lines past the right border. Every non-blank rendered line, ANSI stripped,
# must land at the identical visible width.
test_module_panel_fancy_mode_lines_have_identical_visible_width() {
  resolve_modules "${OPTIONAL_MODULES[@]}"
  local output line output_width first_width="" mismatch=0
  output=$(COLUMNS=78 render_module_panel_fancy)
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    output_width=$(visible_length "$line")
    if [[ -z "$first_width" ]]; then
      first_width=$output_width
    elif [[ "$output_width" != "$first_width" ]]; then
      mismatch=1
    fi
  done <<<"$output"
  assert_eq "0" "$mismatch" "every rendered fancy-mode panel line has the identical visible width (COLUMNS=78)"
}

test_module_panel_fancy_mode_truncates_an_oversized_title_with_ellipsis() {
  local LC_ALL=C.UTF-8
  local saved_title=${MODULE_TITLE[github-cli]}
  MODULE_TITLE[github-cli]='This is a deliberately absurd module title crafted only to force the fancy panel truncation path for this test'
  resolve_modules github-cli
  local output line found=0 matched="" stripped ends_with_ellipsis=0
  output=$(COLUMNS=44 render_module_panel_fancy)
  while IFS= read -r line; do
    if [[ "$line" == *'…'* ]]; then
      found=1
      matched=$line
      break
    fi
  done <<<"$output"
  MODULE_TITLE[github-cli]=$saved_title

  assert_eq "1" "$found" "an oversized module title actually reaches the truncation path (trap guard: fails if nothing matched)"
  assert_eq "44" "$(visible_length "$matched")" "the truncated line still matches the panel's exact width"

  # Strip the box border ("│ " ... " │") to check the CONTENT itself ends
  # with the ellipsis — the full box line legitimately ends with the right
  # border character, not the ellipsis.
  stripped=$(printf '%s' "$matched" | sed -E $'s/\x1b\\[[0-9;]*m//g')
  local content=${stripped#│ }
  content=${content% │}
  [[ "$content" == *'…' ]] && ends_with_ellipsis=1
  assert_eq "1" "$ends_with_ellipsis" "the truncated line's content ends with a single ellipsis character"
}

test_module_panel_marker_reflects_installed_state() {
  local output_installed output_not_installed
  output_installed=$(
    tmux() { :; }
    packages_installed() { return 1; }
    module_panel_marker tmux
  )
  assert_contains 'already installed' "$output_installed" \
    "a module module_install_status reports as installed gets the compact marker"

  output_not_installed=$(module_panel_marker nerd-font-guidance)
  assert_not_contains 'already installed' "$output_not_installed" \
    "a module that is never pre-detected (guidance kind) has no marker"
}

test_module_panel_drops_source_provenance_from_the_panel() {
  local output
  output=$(
    tmux() { :; }
    packages_installed() { return 1; }
    module_panel_marker tmux
  )
  assert_not_contains 'managed source' "$output" "the panel marker does not leak managed/alternate source provenance"
  assert_not_contains 'alternate source' "$output" "the panel marker does not leak managed/alternate source provenance"
}

test_bootstrap_rejects_non_ubuntu_host
test_bootstrap_accepts_ubuntu_2404_host
test_bootstrap_ensure_git_curl_installs_git_via_apt_when_missing
test_bootstrap_ensure_git_curl_fails_cleanly_without_sudo
test_bootstrap_ensure_git_curl_fails_without_curl
test_bootstrap_checkout_dir_derives_from_home
test_bootstrap_ensure_checkout_clones_when_absent
test_bootstrap_ensure_checkout_pulls_when_present
test_bootstrap_launcher_execs_checkout_install
test_bootstrap_ensure_path_appends_when_missing
test_bootstrap_ensure_path_skips_when_present
test_config_install_file_backs_up_existing_destination
test_config_install_file_does_not_back_up_a_missing_destination
test_config_install_file_substitutes_home_marker
test_config_install_all_leaves_zero_markers
test_config_install_all_places_expected_destinations
test_config_module_is_wired_into_the_catalog
test_config_module_dry_run_entrypoint_includes_it
test_config_module_execution_reports_ok
test_gentle_ai_config_module_is_removed_from_the_catalog
test_module_panel_lists_every_resolved_module_exactly_once
test_module_panel_shows_overall_total
test_module_panel_uses_fallback_group_for_a_module_without_a_configured_group
test_module_panel_group_counts_match_listed_modules
test_module_panel_marks_mandatory_modules
test_module_panel_plain_mode_has_no_ansi_escapes_when_no_color_is_set
test_module_panel_plain_mode_has_no_ansi_escapes_on_a_dumb_terminal
test_install_entrypoint_renders_grouped_panel
test_module_panel_fancy_mode_lines_have_identical_visible_width
test_module_panel_fancy_mode_truncates_an_oversized_title_with_ellipsis
test_module_panel_marker_reflects_installed_state
test_module_panel_drops_source_provenance_from_the_panel

if (( failures > 0 )); then
  exit 1
fi
