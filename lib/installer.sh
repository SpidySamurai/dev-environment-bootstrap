#!/usr/bin/env bash

# Defaulted defensively so this file can be sourced (and its functions unit
# tested) before lib/privileges.sh runs its real sudo negotiation.
PRIVILEGES_AVAILABLE=${PRIVILEGES_AVAILABLE:-0}

npm_global_package_installed() {
  local package=$1 node_path node_bin node_prefix package_root
  local -a package_roots=()

  if [[ -n ${NODE_PATH:-} ]]; then
    IFS=: read -r -a package_roots <<< "$NODE_PATH"
    for package_root in "${package_roots[@]}"; do
      [[ -f $package_root/$package/package.json ]] && return 0
    done
  fi

  node_path=$(command -v node) || return 1
  if command -v readlink >/dev/null 2>&1; then
    node_path=$(readlink -f "$node_path" 2>/dev/null || printf '%s' "$node_path")
  fi
  node_bin=${node_path%/*}
  [[ $node_bin != "$node_path" ]] || return 1
  node_prefix=${node_bin%/*}
  [[ $node_prefix != "$node_bin" ]] || return 1

  [[ -f $node_prefix/lib/node_modules/$package/package.json ]]
}

module_has_command_evidence() {
  [[ -n ${MODULE_COMMANDS[$1]-} ]]
}

module_command_evidence_complete() {
  local module=$1 required_command
  module_has_command_evidence "$module" || return 1

  for required_command in ${MODULE_COMMANDS[$module]}; do
    command -v "$required_command" >/dev/null 2>&1 || return 1
  done
}

module_missing_commands() {
  local module=$1 required_command
  local -a missing_commands=()

  module_has_command_evidence "$module" || return 1
  for required_command in ${MODULE_COMMANDS[$module]}; do
    command -v "$required_command" >/dev/null 2>&1 || missing_commands+=("$required_command")
  done
  ((${#missing_commands[@]} == 0)) && return 0

  printf '%s' "${missing_commands[0]}"
  for required_command in "${missing_commands[@]:1}"; do
    printf ', %s' "$required_command"
  done
  return 1
}

module_any_command_available() {
  local module=$1 required_command
  module_has_command_evidence "$module" || return 1

  for required_command in ${MODULE_COMMANDS[$module]}; do
    command -v "$required_command" >/dev/null 2>&1 && return 0
  done
  return 1
}

module_alternate_source_available() {
  local module=$1
  [[ ${MODULE_ALLOW_ALTERNATE_SOURCE[$module]-0} == 1 ]] && module_command_evidence_complete "$module"
}

module_installed() {
  local module=$1 kind=${MODULE_KIND[$1]}
  case "$kind" in
    apt)
      # The catalog stores packages as a space-separated list; splitting it is intended.
      # shellcheck disable=SC2086
      command -v dpkg-query >/dev/null 2>&1 && packages_installed ${MODULE_PACKAGES[$module]}
      ;;
    oh-my-zsh|git-theme|git-clone)
      local install_path=${MODULE_PATH[$module]}
      [[ -d ${install_path/\$HOME/$HOME} ]]
      ;;
    nvm) [[ -s "${NVM_DIR:-$HOME/.nvm}/nvm.sh" ]] ;;
    bun) [[ -x "${BUN_INSTALL:-$HOME/.bun}/bin/bun" ]] ;;
    pnpm) [[ -x "${PNPM_HOME:-$HOME/.local/share/pnpm}/pnpm" ]] ;;
    rustup) [[ -x "${CARGO_HOME:-$HOME/.cargo}/bin/rustup" ]] ;;
    npm)
      npm_global_package_installed "${MODULE_NPM_PACKAGE[$module]}"
      ;;
    github-release|install-script)
      local binary=${MODULE_BINARY[$module]:-$module} binary_path
      binary_path=${MODULE_BINARY_PATH[$module]:-"\$HOME/.local/bin/$binary"}
      [[ -x "${binary_path/\$HOME/$HOME}" ]]
      ;;
    go-tarball)
      [[ -x "${GO_INSTALL_DIR:-$HOME/.local/go}/bin/go" ]]
      ;;
    go-install)
      [[ -x "${GOPATH:-$HOME/go}/bin/${MODULE_BINARY[$module]:-$module}" ]]
      ;;
    guidance) return 1 ;;
    # Unlike a package module, the config-tree module always re-applies:
    # re-running it is how the host picks up an updated config/ tree, and
    # config_install_file backs up whatever it replaces on every run.
    config-tree) return 1 ;;
    *) return 1 ;;
  esac
}

module_install_status() {
  local module=$1
  if module_installed "$module"; then
    if ! module_has_command_evidence "$module" || module_command_evidence_complete "$module"; then
      printf '%s\n' 'installed (managed source)'
      return 0
    fi
  elif module_alternate_source_available "$module"; then
    printf '%s\n' 'installed (alternate source)'
    return 0
  fi
  return 1
}

# npm-kind modules must not assume nvm is the npm provider: if node/npm already
# exist from apt, fnm, volta, or any other source, sourcing a non-existent
# ~/.nvm/nvm.sh must not break the module.
npm_provider_is_nvm() {
  local nvm_dir=${NVM_DIR:-$HOME/.nvm}
  [[ -s "$nvm_dir/nvm.sh" ]]
}

# Downloads a tar.gz release asset and installs one named binary from inside
# it into ~/.local/bin (used for tools with no apt candidate, e.g. zellij).
install_github_release_binary() {
  local module=$1 url=${MODULE_URL[$1]} binary=${MODULE_BINARY[$1]:-$1} tmp_dir found
  tmp_dir=$(mktemp -d)
  local archive="$tmp_dir/archive.tar.gz"

  if ! curl --fail --show-error --location --proto '=https' --tlsv1.2 --retry 3 --retry-delay 2 -o "$archive" "$url"; then
    rm -rf "$tmp_dir"
    return 1
  fi
  if ! tar -xzf "$archive" -C "$tmp_dir"; then
    rm -rf "$tmp_dir"
    return 1
  fi

  found=$(find "$tmp_dir" -maxdepth 4 -type f -name "$binary" | head -n1)
  if [[ -z $found ]]; then
    log "Could not find the $binary binary inside the archive downloaded from $url."
    rm -rf "$tmp_dir"
    return 1
  fi

  mkdir -p "$HOME/.local/bin"
  install -m 0755 "$found" "$HOME/.local/bin/$binary"
  rm -rf "$tmp_dir"
}

# Downloads the official Go tarball and extracts it into ~/.local (producing
# ~/.local/go), matching the measured real source for the go module.
install_go_tarball() {
  local install_dir=${GO_INSTALL_DIR:-$HOME/.local/go} tmp_archive
  tmp_archive=$(mktemp)

  if ! curl --fail --show-error --location --proto '=https' --tlsv1.2 --retry 3 --retry-delay 2 -o "$tmp_archive" "$GO_TARBALL_URL"; then
    rm -f "$tmp_archive"
    return 1
  fi

  rm -rf "$install_dir"
  mkdir -p "$(dirname "$install_dir")"
  if ! tar -C "$(dirname "$install_dir")" -xzf "$tmp_archive"; then
    rm -f "$tmp_archive"
    return 1
  fi
  rm -f "$tmp_archive"
}

# Runs `go install <package>` with the go toolchain installed by the go
# module. Fails cleanly (no crash, no set -e abort) if go is not present yet.
install_go_binary() {
  local module=$1 package=${MODULE_GO_PACKAGE[$1]} go_bin=${GO_INSTALL_DIR:-$HOME/.local/go}/bin/go
  if [[ ! -x $go_bin ]]; then
    log "Go toolchain not found at $go_bin; install the go module first."
    return 1
  fi
  "$go_bin" install "$package"
}

# The actual install commands for a module, isolated from status/skip/dry-run
# handling so callers can capture failures per module.
perform_module_install() {
  local module=$1 kind=$2
  case "$kind" in
    apt)
      [[ $module == base-packages ]] && apt_update
      # The catalog stores packages as a space-separated list; splitting it is intended.
      # shellcheck disable=SC2086
      apt_install ${MODULE_PACKAGES[$module]}
      ;;
    oh-my-zsh)
      run_remote_script "${MODULE_URL[$module]}" bash "ZSH=$HOME/.oh-my-zsh" KEEP_ZSHRC=yes RUNZSH=no CHSH=no
      ;;
    git-theme|git-clone)
      local target=${MODULE_PATH[$module]/\$HOME/$HOME}
      mkdir -p "$(dirname "$target")"
      git clone --depth=1 "${MODULE_URL[$module]}" "$target"
      ;;
    nvm)
      run_remote_script "${MODULE_URL[$module]}" bash
      source_nvm
      nvm install --lts
      ;;
    bun|pnpm)
      run_remote_script "${MODULE_URL[$module]}" bash
      ;;
    rustup)
      run_remote_script "${MODULE_URL[$module]}" sh -- -s -- -y
      ;;
    npm)
      if npm_provider_is_nvm; then
        source_nvm
      fi
      if ! command -v npm >/dev/null 2>&1; then
        log 'npm is not available on PATH; install a Node.js runtime first.'
        return 1
      fi
      npm install -g "${MODULE_NPM_PACKAGE[$module]}"
      ;;
    github-release)
      install_github_release_binary "$module"
      ;;
    go-tarball)
      install_go_tarball
      ;;
    go-install)
      install_go_binary "$module"
      ;;
    install-script)
      run_remote_script "${MODULE_URL[$module]}" "${MODULE_INTERPRETER[$module]:-bash}"
      ;;
    guidance)
      cat <<'EOF'
Nerd Font guidance: install a Nerd Font in Windows Terminal (for example, MesloLGS NF),
then select it in the WSL profile. This installer intentionally does not alter terminal
profiles because they are Windows-host settings.
EOF
      ;;
    config-tree)
      config_install_all
      ;;
  esac
}

install_module() {
  local module=$1 kind=${MODULE_KIND[$1]} status
  if status=$(module_install_status "$module"); then
    log "Skipping $module: $status."
    return 0
  fi
  if ((DRY_RUN)); then
    module_plan_lines "$module"
    return 0
  fi

  log "Installing $module: ${MODULE_TITLE[$module]}"
  perform_module_install "$module" "$kind"
}

audit_module_status() {
  local module=$1 kind=${MODULE_KIND[$1]} missing_list=''
  if [[ $kind == guidance ]]; then
    printf '%s\n' 'manual/host configuration required'
  elif [[ $kind == config-tree ]]; then
    if config_destination_present; then
      printf '%s\n' 'installed (managed source)'
    else
      printf '%s\n' 'missing'
    fi
  elif module_installed "$module"; then
    if ! module_has_command_evidence "$module" || module_command_evidence_complete "$module"; then
      printf '%s\n' 'installed (managed source)'
    else
      missing_list=$(module_missing_commands "$module" || true)
      printf 'partial (managed source; missing commands: %s)\n' "$missing_list"
    fi
  elif module_has_command_evidence "$module"; then
    missing_list=$(module_missing_commands "$module" || true)
    if [[ -z $missing_list ]]; then
      if [[ ${MODULE_ALLOW_ALTERNATE_SOURCE[$module]-0} == 1 ]]; then
        printf '%s\n' 'installed (alternate source)'
      else
        printf '%s\n' 'partial (managed source not detected; commands available)'
      fi
    elif module_any_command_available "$module"; then
      if [[ ${MODULE_ALLOW_ALTERNATE_SOURCE[$module]-0} == 1 ]]; then
        printf 'partial (alternate source; missing commands: %s)\n' "$missing_list"
      else
        printf 'partial (managed source not detected; missing commands: %s)\n' "$missing_list"
      fi
    else
      printf '%s\n' 'missing'
    fi
  else
    printf '%s\n' 'missing'
  fi
}

count_audit_status() {
  local status=$1 managed_name=$2 alternate_name=$3 partial_name=$4 missing_name=$5 manual_name=$6
  case "$status" in
    'installed (managed source)') printf -v "$managed_name" '%d' "$(( ${!managed_name} + 1 ))" ;;
    'installed (alternate source)') printf -v "$alternate_name" '%d' "$(( ${!alternate_name} + 1 ))" ;;
    partial*) printf -v "$partial_name" '%d' "$(( ${!partial_name} + 1 ))" ;;
    missing) printf -v "$missing_name" '%d' "$(( ${!missing_name} + 1 ))" ;;
    *) printf -v "$manual_name" '%d' "$(( ${!manual_name} + 1 ))" ;;
  esac
}

audit_environment() {
  local module status
  local mandatory_managed=0 mandatory_alternate=0 mandatory_partial=0 mandatory_missing=0 mandatory_manual=0
  local optional_managed=0 optional_alternate=0 optional_partial=0 optional_missing=0 optional_manual=0

  if [[ -z ${HOME:-} ]]; then
    printf '%s\n' 'Unable to audit: HOME is not set.' >&2
    return 1
  fi

  printf '%s\n' 'Environment audit'
  printf '%s\n' 'Read-only inventory: no selection, confirmation, sudo, package installation, downloads, or host changes are performed.'
  printf '%-24s %-10s %s\n' 'Module' 'Scope' 'Status'
  printf '%-24s %-10s %s\n' '------------------------' '----------' '------------------------------------'

  for module in "${MANDATORY_MODULES[@]}"; do
    status=$(audit_module_status "$module")
    printf '%-24s %-10s %s\n' "$module" 'mandatory' "$status"
    count_audit_status "$status" mandatory_managed mandatory_alternate mandatory_partial mandatory_missing mandatory_manual
  done

  for module in "${OPTIONAL_MODULES[@]}"; do
    status=$(audit_module_status "$module")
    printf '%-24s %-10s %s\n' "$module" 'optional' "$status"
    count_audit_status "$status" optional_managed optional_alternate optional_partial optional_missing optional_manual
  done

  cat <<'EOF'

Manual/host configuration checks
  - Fonts and terminal profile: manual/host configuration required.
  - Provider authentication (GitHub and coding-agent providers): manual/host configuration required.
  - SSH keys: manual/host configuration required.
  - WSL Docker integration, systemd, and docker-group access: manual/host configuration required.
EOF
  printf 'Summary: mandatory managed=%d alternate=%d partial=%d missing=%d manual=%d; optional managed=%d alternate=%d partial=%d missing=%d manual=%d.\n' \
    "$mandatory_managed" "$mandatory_alternate" "$mandatory_partial" "$mandatory_missing" "$mandatory_manual" \
    "$optional_managed" "$optional_alternate" "$optional_partial" "$optional_missing" "$optional_manual"
}

config_path_exists() {
  [[ -e $1 || -L $1 ]]
}

# Reduces captured module stderr to a single readable line for the execution
# report's Detail column. A tool like curl redraws its progress
# meter in place using carriage returns rather than newlines; captured
# verbatim, the whole meter becomes one enormous "line" with no \n in it,
# which blows out a fixed-width table. This strips ANSI escapes, treats \r as
# a line break, drops progress-meter noise, and keeps the last meaningful
# line, truncated to a sensible width.
sanitize_module_reason() {
  local raw=$1 line last_meaningful='' max_width=200

  raw=$(printf '%s' "$raw" | sed -E 's/\x1b\[[0-9;]*[a-zA-Z]//g')
  raw=${raw//$'\r'/$'\n'}

  while IFS= read -r line; do
    line=$(printf '%s' "$line" | tr -s '[:space:]' ' ')
    line=${line#"${line%%[![:space:]]*}"}
    line=${line%"${line##*[![:space:]]}"}
    [[ -z $line ]] && continue
    # curl-style progress-meter noise: its header row ("% Total ..."), the
    # continuation header row ("Dload  Upload ..."), and its numeric data
    # rows (digits, percent signs, colons, dots, dashes, and spaces only).
    [[ $line == '% Total'* ]] && continue
    [[ $line =~ [Dd]load ]] && continue
    [[ $line =~ ^[0-9%.:\ -]+$ ]] && continue
    last_meaningful=$line
  done <<<"$raw"

  if ((${#last_meaningful} > max_width)); then
    printf '%s' "${last_meaningful:0:max_width}…"
  else
    printf '%s' "$last_meaningful"
  fi
}

declare -A MODULE_RESULT=()
declare -A MODULE_REASON=()

module_is_mandatory() {
  local module=$1 candidate
  for candidate in "${MANDATORY_MODULES[@]}"; do
    [[ $candidate == "$module" ]] && return 0
  done
  return 1
}

# Runs one module's install commands in isolation: it never lets a failure
# abort the run. It records ok / failed / skipped / manual into MODULE_RESULT
# and MODULE_REASON, and for failures captures a short reason (privilege
# gate, or the tail of the module's own stderr).
run_module_isolated() {
  local module=$1 kind=${MODULE_KIND[$1]} status stderr_file exit_code=0

  if [[ $kind == guidance ]]; then
    install_module "$module"
    MODULE_RESULT[$module]=manual
    MODULE_REASON[$module]='manual/host configuration required'
    return 0
  fi

  if status=$(module_install_status "$module"); then
    log "Skipping $module: $status."
    MODULE_RESULT[$module]=skipped
    MODULE_REASON[$module]=$status
    return 0
  fi

  if [[ $kind == apt ]] && ((PRIVILEGES_AVAILABLE == 0)); then
    log "Skipping $module: failed (no privileges)."
    MODULE_RESULT[$module]=failed
    MODULE_REASON[$module]='no privileges'
    return 0
  fi

  log "Installing $module: ${MODULE_TITLE[$module]}"
  stderr_file=$(mktemp)
  if perform_module_install "$module" "$kind" 2>"$stderr_file"; then
    MODULE_RESULT[$module]=ok
    MODULE_REASON[$module]=''
  else
    exit_code=$?
    MODULE_RESULT[$module]=failed
    MODULE_REASON[$module]=$(sanitize_module_reason "$(cat "$stderr_file")")
    [[ -z ${MODULE_REASON[$module]} ]] && MODULE_REASON[$module]="exit code $exit_code"
  fi
  cat "$stderr_file" >&2
  rm -f "$stderr_file"
}

print_execution_report() {
  local module
  printf '\n%s\n' 'Installation report'
  printf '%-24s %-10s %s\n' 'Module' 'Status' 'Detail'
  printf '%-24s %-10s %s\n' '------------------------' '----------' '------------------------------------'
  for module in "${RESOLVED_MODULES[@]}"; do
    printf '%-24s %-10s %s\n' "$module" "${MODULE_RESULT[$module]:-unknown}" "${MODULE_REASON[$module]:-}"
  done
  printf '\n'
}

execute_plan() {
  local module has_mandatory_failure=0

  MODULE_RESULT=()
  MODULE_REASON=()

  for module in "${RESOLVED_MODULES[@]}"; do
    run_module_isolated "$module"
  done


  print_execution_report

  for module in "${RESOLVED_MODULES[@]}"; do
    if [[ ${MODULE_RESULT[$module]-} == failed ]] && module_is_mandatory "$module"; then
      has_mandatory_failure=1
    fi
  done

  ((has_mandatory_failure)) && return 1
  return 0
}
