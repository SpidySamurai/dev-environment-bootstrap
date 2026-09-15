#!/usr/bin/env bash

# Module metadata is intentionally declarative: selection, dependency resolution,
# plan rendering, and installation all use this single catalog.
declare -a MODULE_IDS=()
declare -a MANDATORY_MODULES=()
declare -a OPTIONAL_MODULES=()
declare -a RESOLVED_MODULES=()
declare -A MODULE_TITLE=()
declare -A MODULE_GROUP=()
declare -A MODULE_DEPS=()
declare -A MODULE_KIND=()
declare -A MODULE_PACKAGES=()
declare -A MODULE_URL=()
declare -A MODULE_NPM_PACKAGE=()
declare -A MODULE_PATH=()
declare -A MODULE_COMMANDS=()
declare -A MODULE_ALLOW_ALTERNATE_SOURCE=()
declare -A MODULE_SELECTED=()

module_init() {
  MODULE_IDS=(
    base-packages zsh oh-my-zsh powerlevel10k nerd-font-guidance
    container-prerequisites cli-modern multiplexers docker node-nvm bun go rust
    github-cli agent-gentle-ai agent-pi agent-codex agent-claude-code agent-opencode agent-herdr
  )
  MANDATORY_MODULES=(base-packages zsh oh-my-zsh powerlevel10k nerd-font-guidance)
  OPTIONAL_MODULES=(
    cli-modern multiplexers docker node-nvm bun go rust github-cli
    agent-gentle-ai agent-pi agent-codex agent-claude-code agent-opencode agent-herdr
  )

  MODULE_TITLE=()
  MODULE_GROUP=()
  MODULE_DEPS=()
  MODULE_KIND=()
  MODULE_PACKAGES=()
  MODULE_URL=()
  MODULE_NPM_PACKAGE=()
  MODULE_PATH=()
  MODULE_COMMANDS=()
  MODULE_ALLOW_ALTERNATE_SOURCE=()

  MODULE_TITLE[base-packages]='Core packages (curl, git, certificates, fonts)'
  MODULE_GROUP[base-packages]='Mandatory baseline'
  MODULE_KIND[base-packages]=apt
  MODULE_PACKAGES[base-packages]='ca-certificates curl git unzip fontconfig software-properties-common'
  MODULE_COMMANDS[base-packages]='curl git'

  MODULE_TITLE[zsh]='Zsh shell'
  MODULE_GROUP[zsh]='Mandatory baseline'
  MODULE_KIND[zsh]=apt
  MODULE_PACKAGES[zsh]='zsh'
  MODULE_COMMANDS[zsh]='zsh'

  MODULE_TITLE[oh-my-zsh]='Oh My Zsh'
  MODULE_GROUP[oh-my-zsh]='Mandatory baseline'
  MODULE_DEPS[oh-my-zsh]='zsh'
  MODULE_KIND[oh-my-zsh]=oh-my-zsh
  MODULE_URL[oh-my-zsh]='https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh'
  MODULE_PATH[oh-my-zsh]='$HOME/.oh-my-zsh'

  MODULE_TITLE[powerlevel10k]='Powerlevel10k prompt theme'
  MODULE_GROUP[powerlevel10k]='Mandatory baseline'
  MODULE_DEPS[powerlevel10k]='oh-my-zsh'
  MODULE_KIND[powerlevel10k]=git-theme
  MODULE_URL[powerlevel10k]='https://github.com/romkatv/powerlevel10k.git'
  MODULE_PATH[powerlevel10k]='$HOME/.oh-my-zsh/custom/themes/powerlevel10k'

  MODULE_TITLE[nerd-font-guidance]='Nerd Font setup guidance'
  MODULE_GROUP[nerd-font-guidance]='Mandatory baseline'
  MODULE_KIND[nerd-font-guidance]=guidance

  MODULE_TITLE[container-prerequisites]='Docker prerequisites'
  MODULE_GROUP[container-prerequisites]='Containers (dependency)'
  MODULE_KIND[container-prerequisites]=apt
  MODULE_PACKAGES[container-prerequisites]='apt-transport-https gnupg lsb-release'

  MODULE_TITLE[cli-modern]='Modern CLI tooling (fzf, zoxide, direnv, bat, eza, ripgrep, fd, delta)'
  MODULE_GROUP[cli-modern]='Modern CLI'
  MODULE_KIND[cli-modern]=apt
  MODULE_PACKAGES[cli-modern]='fzf zoxide direnv bat eza ripgrep fd-find git-delta'
  MODULE_COMMANDS[cli-modern]='fzf zoxide direnv batcat eza rg fdfind delta'
  MODULE_ALLOW_ALTERNATE_SOURCE[cli-modern]=1

  MODULE_TITLE[multiplexers]='Terminal multiplexers (Zellij and tmux)'
  MODULE_GROUP[multiplexers]='Terminal workflow'
  MODULE_KIND[multiplexers]=apt
  MODULE_PACKAGES[multiplexers]='zellij tmux'
  MODULE_COMMANDS[multiplexers]='zellij tmux'
  MODULE_ALLOW_ALTERNATE_SOURCE[multiplexers]=1

  MODULE_TITLE[docker]='Docker Engine packages'
  MODULE_GROUP[docker]='Containers'
  MODULE_DEPS[docker]='container-prerequisites'
  MODULE_KIND[docker]=apt
  MODULE_PACKAGES[docker]='docker.io docker-compose-v2'
  MODULE_COMMANDS[docker]='docker'
  MODULE_ALLOW_ALTERNATE_SOURCE[docker]=1

  MODULE_TITLE[node-nvm]='Node.js LTS via nvm'
  MODULE_GROUP[node-nvm]='Runtimes'
  MODULE_DEPS[node-nvm]='base-packages'
  MODULE_KIND[node-nvm]=nvm
  MODULE_URL[node-nvm]='https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh'
  MODULE_COMMANDS[node-nvm]='node npm'
  MODULE_ALLOW_ALTERNATE_SOURCE[node-nvm]=1

  MODULE_TITLE[bun]='Bun runtime'
  MODULE_GROUP[bun]='Runtimes'
  MODULE_DEPS[bun]='base-packages'
  MODULE_KIND[bun]=bun
  MODULE_URL[bun]='https://bun.sh/install'
  MODULE_COMMANDS[bun]='bun'
  MODULE_ALLOW_ALTERNATE_SOURCE[bun]=1

  MODULE_TITLE[go]='Go toolchain'
  MODULE_GROUP[go]='Runtimes'
  MODULE_KIND[go]=apt
  MODULE_PACKAGES[go]='golang-go'
  MODULE_COMMANDS[go]='go'
  MODULE_ALLOW_ALTERNATE_SOURCE[go]=1

  MODULE_TITLE[rust]='Rust toolchain via rustup'
  MODULE_GROUP[rust]='Runtimes'
  MODULE_DEPS[rust]='base-packages'
  MODULE_KIND[rust]=rustup
  MODULE_URL[rust]='https://sh.rustup.rs'
  MODULE_COMMANDS[rust]='rustc cargo'
  MODULE_ALLOW_ALTERNATE_SOURCE[rust]=1

  MODULE_TITLE[github-cli]='GitHub CLI'
  MODULE_GROUP[github-cli]='Developer services'
  MODULE_KIND[github-cli]=apt
  MODULE_PACKAGES[github-cli]='gh'
  MODULE_COMMANDS[github-cli]='gh'
  MODULE_ALLOW_ALTERNATE_SOURCE[github-cli]=1

  MODULE_TITLE[agent-gentle-ai]='Gentle AI CLI'
  MODULE_GROUP[agent-gentle-ai]='Coding agents'
  MODULE_DEPS[agent-gentle-ai]='node-nvm'
  MODULE_KIND[agent-gentle-ai]=npm
  MODULE_NPM_PACKAGE[agent-gentle-ai]='gentle-ai'
  MODULE_COMMANDS[agent-gentle-ai]='gentle-ai'
  MODULE_ALLOW_ALTERNATE_SOURCE[agent-gentle-ai]=1

  MODULE_TITLE[agent-pi]='Pi coding agent'
  MODULE_GROUP[agent-pi]='Coding agents'
  MODULE_DEPS[agent-pi]='node-nvm'
  MODULE_KIND[agent-pi]=npm
  MODULE_NPM_PACKAGE[agent-pi]='@earendil-works/pi-coding-agent'
  MODULE_COMMANDS[agent-pi]='pi'
  MODULE_ALLOW_ALTERNATE_SOURCE[agent-pi]=1

  MODULE_TITLE[agent-codex]='OpenAI Codex CLI'
  MODULE_GROUP[agent-codex]='Coding agents'
  MODULE_DEPS[agent-codex]='node-nvm'
  MODULE_KIND[agent-codex]=npm
  MODULE_NPM_PACKAGE[agent-codex]='@openai/codex'
  MODULE_COMMANDS[agent-codex]='codex'
  MODULE_ALLOW_ALTERNATE_SOURCE[agent-codex]=1

  MODULE_TITLE[agent-claude-code]='Claude Code'
  MODULE_GROUP[agent-claude-code]='Coding agents'
  MODULE_DEPS[agent-claude-code]='node-nvm'
  MODULE_KIND[agent-claude-code]=npm
  MODULE_NPM_PACKAGE[agent-claude-code]='@anthropic-ai/claude-code'
  MODULE_COMMANDS[agent-claude-code]='claude'
  MODULE_ALLOW_ALTERNATE_SOURCE[agent-claude-code]=1

  MODULE_TITLE[agent-opencode]='OpenCode'
  MODULE_GROUP[agent-opencode]='Coding agents'
  MODULE_DEPS[agent-opencode]='node-nvm'
  MODULE_KIND[agent-opencode]=npm
  MODULE_NPM_PACKAGE[agent-opencode]='opencode-ai'
  MODULE_COMMANDS[agent-opencode]='opencode'
  MODULE_ALLOW_ALTERNATE_SOURCE[agent-opencode]=1

  MODULE_TITLE[agent-herdr]='herdr'
  MODULE_GROUP[agent-herdr]='Coding agents'
  MODULE_DEPS[agent-herdr]='node-nvm'
  MODULE_KIND[agent-herdr]=npm
  MODULE_NPM_PACKAGE[agent-herdr]='herdr'
  MODULE_COMMANDS[agent-herdr]='herdr'
  MODULE_ALLOW_ALTERNATE_SOURCE[agent-herdr]=1
}

module_exists() {
  local candidate=$1 id
  for id in "${MODULE_IDS[@]}"; do
    [[ "$id" == "$candidate" ]] && return 0
  done
  return 1
}

optional_module_ids() {
  printf '%s\n' "${OPTIONAL_MODULES[@]}"
}

add_module_with_dependencies() {
  local module=$1 dependency
  if [[ -n ${MODULE_SELECTED[$module]+x} ]]; then
    return 0
  fi
  if ! module_exists "$module"; then
    printf 'Unknown module: %s\n' "$module" >&2
    return 2
  fi

  MODULE_SELECTED[$module]=visiting
  for dependency in ${MODULE_DEPS[$module]-}; do
    if [[ ${MODULE_SELECTED[$dependency]-} == visiting ]]; then
      printf 'Module dependency cycle detected at: %s\n' "$dependency" >&2
      return 2
    fi
    add_module_with_dependencies "$dependency"
  done
  MODULE_SELECTED[$module]=selected
  RESOLVED_MODULES+=("$module")
}

resolve_modules() {
  local module
  RESOLVED_MODULES=()
  MODULE_SELECTED=()

  for module in "${MANDATORY_MODULES[@]}"; do
    add_module_with_dependencies "$module"
  done
  for module in "$@"; do
    [[ -n "$module" ]] && add_module_with_dependencies "$module"
  done
}

expand_requested_modules() {
  local requested=$1 module
  if [[ "$requested" == all ]]; then
    printf '%s\n' "${OPTIONAL_MODULES[@]}"
    return 0
  fi
  IFS=',' read -r -a _requested_parts <<< "$requested"
  for module in "${_requested_parts[@]}"; do
    [[ -n "$module" ]] && printf '%s\n' "$module"
  done
}

module_plan_lines() {
  local module=$1 kind=${MODULE_KIND[$1]}
  printf 'Module: %s — %s\n' "$module" "${MODULE_TITLE[$module]}"
  case "$kind" in
    apt)
      [[ "$module" == base-packages ]] && printf '  sudo apt-get update\n'
      printf '  sudo apt-get install -y %s\n' "${MODULE_PACKAGES[$module]}"
      ;;
    oh-my-zsh)
      printf "  curl --fail --show-error --location --proto '=https' --tlsv1.2 --retry 3 %s | env KEEP_ZSHRC=yes RUNZSH=no CHSH=no bash\n" "${MODULE_URL[$module]}"
      ;;
    git-theme)
      printf '  git clone --depth=1 %s %s\n' "${MODULE_URL[$module]}" "${MODULE_PATH[$module]}"
      ;;
    nvm)
      printf "  curl --fail --show-error --location --proto '=https' --tlsv1.2 --retry 3 %s | bash; nvm install --lts\n" "${MODULE_URL[$module]}"
      ;;
    bun)
      printf "  curl --fail --show-error --location --proto '=https' --tlsv1.2 --retry 3 %s | bash\n" "${MODULE_URL[$module]}"
      ;;
    rustup)
      printf "  curl --fail --show-error --location --proto '=https' --tlsv1.2 --retry 3 %s | sh -s -- -y\n" "${MODULE_URL[$module]}"
      ;;
    npm)
      printf '  npm install -g %s\n' "${MODULE_NPM_PACKAGE[$module]}"
      ;;
    guidance)
      printf '  Print Nerd Font installation and terminal-profile guidance.\n'
      ;;
  esac
}

render_dry_run_plan() {
  local module status
  for module in "${RESOLVED_MODULES[@]}"; do
    if status=$(module_install_status "$module"); then
      printf 'Skipping %s: %s.\n' "$module" "$status"
    else
      module_plan_lines "$module"
    fi
  done
}

module_init
