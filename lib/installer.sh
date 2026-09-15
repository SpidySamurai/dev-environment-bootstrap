#!/usr/bin/env bash

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
      command -v dpkg-query >/dev/null 2>&1 && packages_installed ${MODULE_PACKAGES[$module]}
      ;;
    oh-my-zsh|git-theme)
      local install_path=${MODULE_PATH[$module]}
      [[ -d ${install_path/\$HOME/$HOME} ]]
      ;;
    nvm) [[ -s "${NVM_DIR:-$HOME/.nvm}/nvm.sh" ]] ;;
    bun) [[ -x "${BUN_INSTALL:-$HOME/.bun}/bin/bun" ]] ;;
    rustup) [[ -x "${CARGO_HOME:-$HOME/.cargo}/bin/rustup" ]] ;;
    npm)
      npm_global_package_installed "${MODULE_NPM_PACKAGE[$module]}"
      ;;
    guidance) return 1 ;;
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
  case "$kind" in
    apt)
      [[ $module == base-packages ]] && apt_update
      apt_install ${MODULE_PACKAGES[$module]}
      ;;
    oh-my-zsh)
      run_remote_script "${MODULE_URL[$module]}" bash KEEP_ZSHRC=yes RUNZSH=no CHSH=no
      ;;
    git-theme)
      mkdir -p "$HOME/.oh-my-zsh/custom/themes"
      git clone --depth=1 "${MODULE_URL[$module]}" "$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
      ;;
    nvm)
      run_remote_script "${MODULE_URL[$module]}" bash
      source_nvm
      nvm install --lts
      ;;
    bun)
      run_remote_script "${MODULE_URL[$module]}" bash
      ;;
    rustup)
      run_remote_script "${MODULE_URL[$module]}" sh -s -- -y
      ;;
    npm)
      source_nvm
      npm install -g "${MODULE_NPM_PACKAGE[$module]}"
      ;;
    guidance)
      cat <<'EOF'
Nerd Font guidance: install a Nerd Font in Windows Terminal (for example, MesloLGS NF),
then select it in the WSL profile. This installer intentionally does not alter terminal
profiles because they are Windows-host settings.
EOF
      ;;
  esac
}

audit_module_status() {
  local module=$1 kind=${MODULE_KIND[$1]} missing_commands=''
  if [[ $kind == guidance ]]; then
    printf '%s\n' 'manual/host configuration required'
  elif module_installed "$module"; then
    if ! module_has_command_evidence "$module" || module_command_evidence_complete "$module"; then
      printf '%s\n' 'installed (managed source)'
    else
      missing_commands=$(module_missing_commands "$module" || true)
      printf 'partial (managed source; missing commands: %s)\n' "$missing_commands"
    fi
  elif module_has_command_evidence "$module"; then
    missing_commands=$(module_missing_commands "$module" || true)
    if [[ -z $missing_commands ]]; then
      if [[ ${MODULE_ALLOW_ALTERNATE_SOURCE[$module]-0} == 1 ]]; then
        printf '%s\n' 'installed (alternate source)'
      else
        printf '%s\n' 'partial (managed source not detected; commands available)'
      fi
    elif module_any_command_available "$module"; then
      if [[ ${MODULE_ALLOW_ALTERNATE_SOURCE[$module]-0} == 1 ]]; then
        printf 'partial (alternate source; missing commands: %s)\n' "$missing_commands"
      else
        printf 'partial (managed source not detected; missing commands: %s)\n' "$missing_commands"
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
  local module status scope
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

configure_zsh() {
  local zshrc="$HOME/.zshrc" p10k="$HOME/.p10k.zsh"
  if config_path_exists "$zshrc"; then
    log "Preserving existing $zshrc; no shell configuration was overwritten."
    log 'To enable Powerlevel10k manually, set ZSH_THEME="powerlevel10k/powerlevel10k" in your existing ~/.zshrc.'
  elif ((DRY_RUN)); then
    log "[dry-run] Would create $zshrc with the minimal Oh My Zsh and Powerlevel10k configuration."
  else
    cat >"$zshrc" <<'EOF'
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"
plugins=(git)
source "$ZSH/oh-my-zsh.sh"
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh
EOF
    log "Created $zshrc. Run 'p10k configure' in a new Zsh session to create your prompt preferences."
  fi

  if config_path_exists "$p10k"; then
    log "Preserving existing $p10k."
  fi
}

execute_plan() {
  local module
  for module in "${RESOLVED_MODULES[@]}"; do
    install_module "$module"
  done
  configure_zsh
}
