#!/usr/bin/env bash
# The catalog arrays are read by lib/installer.sh and lib/ui.sh (SC2034), and
# install paths keep $HOME literal until install time (SC2016).
# shellcheck disable=SC2034,SC2016

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
declare -A MODULE_BINARY=()
declare -A MODULE_BINARY_PATH=()
declare -A MODULE_GO_PACKAGE=()
declare -A MODULE_INTERPRETER=()

# Versioned sources for kinds that download a specific artifact. Bump these
# deliberately: a pinned release installs the same binary on every machine.
readonly ZELLIJ_VERSION='0.46.0'
readonly ZELLIJ_RELEASE_URL="https://github.com/zellij-org/zellij/releases/download/v${ZELLIJ_VERSION}/zellij-x86_64-unknown-linux-musl.tar.gz"
readonly GO_VERSION='1.27.1'
readonly GO_TARBALL_URL="https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz"
readonly PNPM_INSTALL_URL='https://get.pnpm.io/install.sh'

# These agent CLIs ship their own installer scripts rather than a package
# registry entry. Each URL is the vendor's documented Linux install command.
#
# gentle-ai stays on main on purpose: its installer resolves and downloads the
# latest stable release itself, whatever ref the script comes from, so a
# tagged script URL would not pin the installed version. It would only run an
# older copy of the installer against newer releases.
readonly GENTLE_AI_INSTALL_URL='https://raw.githubusercontent.com/Gentleman-Programming/gentle-ai/main/scripts/install.sh'
readonly CLAUDE_CODE_INSTALL_URL='https://claude.ai/install.sh'
readonly OPENCODE_INSTALL_URL='https://opencode.ai/install'
readonly HERDR_INSTALL_URL='https://herdr.dev/install.sh'

module_init() {
  MODULE_IDS=(
    base-packages zsh oh-my-zsh powerlevel10k nerd-font-guidance
    container-prerequisites cli-modern tmux zellij docker node-nvm bun pnpm go
    lazygit rust github-cli zsh-autosuggestions zsh-syntax-highlighting
    agent-gentle-ai agent-pi agent-codex agent-claude-code agent-opencode agent-herdr
    angular-cli spidy-config
  )
  MANDATORY_MODULES=(base-packages zsh oh-my-zsh powerlevel10k nerd-font-guidance)
  OPTIONAL_MODULES=(
    cli-modern tmux zellij docker node-nvm bun pnpm go lazygit rust github-cli
    zsh-autosuggestions zsh-syntax-highlighting
    agent-gentle-ai agent-pi agent-codex agent-claude-code agent-opencode agent-herdr
    angular-cli spidy-config
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
  MODULE_BINARY=()
  MODULE_GO_PACKAGE=()

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
  # Oh My Zsh publishes no tags or releases, and its installer clones master
  # anyway, so there is no stable ref to pin to.
  MODULE_URL[oh-my-zsh]='https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh'
  MODULE_PATH[oh-my-zsh]='$HOME/.oh-my-zsh'

  MODULE_TITLE[powerlevel10k]='Powerlevel10k prompt theme'
  MODULE_GROUP[powerlevel10k]='Mandatory baseline'
  MODULE_DEPS[powerlevel10k]='oh-my-zsh'
  MODULE_KIND[powerlevel10k]=git-clone
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

  MODULE_TITLE[tmux]='tmux terminal multiplexer'
  MODULE_GROUP[tmux]='Terminal workflow'
  MODULE_KIND[tmux]=apt
  MODULE_PACKAGES[tmux]='tmux'
  MODULE_COMMANDS[tmux]='tmux'
  MODULE_ALLOW_ALTERNATE_SOURCE[tmux]=1

  # zellij has no apt candidate on Ubuntu 24.04 (verified: apt-cache policy
  # zellij returns no candidate). Install the upstream release binary instead.
  MODULE_TITLE[zellij]='Zellij terminal multiplexer'
  MODULE_GROUP[zellij]='Terminal workflow'
  MODULE_KIND[zellij]=github-release
  MODULE_URL[zellij]=$ZELLIJ_RELEASE_URL
  MODULE_BINARY[zellij]='zellij'
  MODULE_COMMANDS[zellij]='zellij'
  MODULE_ALLOW_ALTERNATE_SOURCE[zellij]=1

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

  MODULE_TITLE[pnpm]='pnpm package manager'
  MODULE_GROUP[pnpm]='Runtimes'
  MODULE_DEPS[pnpm]='base-packages'
  MODULE_KIND[pnpm]=pnpm
  MODULE_URL[pnpm]=$PNPM_INSTALL_URL
  MODULE_COMMANDS[pnpm]='pnpm'
  MODULE_ALLOW_ALTERNATE_SOURCE[pnpm]=1

  # golang-go on Ubuntu 24.04 apt is 1.22; the official tarball is the
  # measured real source and keeps parity with the reference host (1.27.x).
  MODULE_TITLE[go]='Go toolchain'
  MODULE_GROUP[go]='Runtimes'
  MODULE_KIND[go]=go-tarball
  MODULE_COMMANDS[go]='go'
  MODULE_ALLOW_ALTERNATE_SOURCE[go]=1

  MODULE_TITLE[lazygit]='lazygit terminal Git UI'
  MODULE_GROUP[lazygit]='Terminal workflow'
  MODULE_DEPS[lazygit]='go'
  MODULE_KIND[lazygit]=go-install
  MODULE_GO_PACKAGE[lazygit]='github.com/jesseduffield/lazygit@latest'
  MODULE_BINARY[lazygit]='lazygit'
  MODULE_COMMANDS[lazygit]='lazygit'
  MODULE_ALLOW_ALTERNATE_SOURCE[lazygit]=1

  MODULE_TITLE[rust]='Rust toolchain via rustup'
  MODULE_GROUP[rust]='Runtimes'
  MODULE_DEPS[rust]='base-packages'
  MODULE_KIND[rust]=rustup
  MODULE_URL[rust]='https://sh.rustup.rs'
  MODULE_COMMANDS[rust]='rustc cargo'
  MODULE_ALLOW_ALTERNATE_SOURCE[rust]=1

  # gh's real source on the reference host is ~/.local/bin/gh, but apt gh is
  # also acceptable and simpler; either way audit/detection treats an
  # existing ~/.local/bin/gh as already installed via MODULE_COMMANDS below.
  MODULE_TITLE[github-cli]='GitHub CLI'
  MODULE_GROUP[github-cli]='Developer services'
  MODULE_KIND[github-cli]=apt
  MODULE_PACKAGES[github-cli]='gh'
  MODULE_COMMANDS[github-cli]='gh'
  MODULE_ALLOW_ALTERNATE_SOURCE[github-cli]=1

  MODULE_TITLE[zsh-autosuggestions]='zsh-autosuggestions plugin'
  MODULE_GROUP[zsh-autosuggestions]='Shell plugins'
  MODULE_DEPS[zsh-autosuggestions]='oh-my-zsh'
  MODULE_KIND[zsh-autosuggestions]=git-clone
  MODULE_URL[zsh-autosuggestions]='https://github.com/zsh-users/zsh-autosuggestions.git'
  MODULE_PATH[zsh-autosuggestions]='$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions'

  MODULE_TITLE[zsh-syntax-highlighting]='zsh-syntax-highlighting plugin'
  MODULE_GROUP[zsh-syntax-highlighting]='Shell plugins'
  MODULE_DEPS[zsh-syntax-highlighting]='oh-my-zsh'
  MODULE_KIND[zsh-syntax-highlighting]=git-clone
  MODULE_URL[zsh-syntax-highlighting]='https://github.com/zsh-users/zsh-syntax-highlighting.git'
  MODULE_PATH[zsh-syntax-highlighting]='$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting'

  # gentle-ai is not an npm package (verified: registry.npmjs.org 404s for
  # it). Its verified real source is the documented Linux install command in
  # the Gentleman-Programming/gentle-ai README.
  MODULE_TITLE[agent-gentle-ai]='Gentle AI CLI'
  MODULE_GROUP[agent-gentle-ai]='Coding agents'
  MODULE_DEPS[agent-gentle-ai]='base-packages'
  MODULE_KIND[agent-gentle-ai]=install-script
  MODULE_URL[agent-gentle-ai]=$GENTLE_AI_INSTALL_URL
  MODULE_INTERPRETER[agent-gentle-ai]='bash'
  MODULE_BINARY[agent-gentle-ai]='gentle-ai'
  MODULE_COMMANDS[agent-gentle-ai]='gentle-ai'
  MODULE_ALLOW_ALTERNATE_SOURCE[agent-gentle-ai]=1

  MODULE_TITLE[agent-pi]='Pi coding agent'
  MODULE_GROUP[agent-pi]='Coding agents'
  MODULE_DEPS[agent-pi]='node-nvm'
  MODULE_KIND[agent-pi]=npm
  MODULE_NPM_PACKAGE[agent-pi]='@earendil-works/pi-coding-agent'
  MODULE_COMMANDS[agent-pi]='pi'
  MODULE_ALLOW_ALTERNATE_SOURCE[agent-pi]=1

  # codex's verified real source is the official @openai/codex npm package
  # (version 0.155.0, bin `codex`); it self-manages a standalone binary under
  # ~/.codex/packages/standalone/ after install, so it uses the npm kind like
  # the other node-based agent modules instead of install-script.
  MODULE_TITLE[agent-codex]='OpenAI Codex CLI'
  MODULE_GROUP[agent-codex]='Coding agents'
  MODULE_DEPS[agent-codex]='node-nvm'
  MODULE_KIND[agent-codex]=npm
  MODULE_NPM_PACKAGE[agent-codex]='@openai/codex'
  MODULE_COMMANDS[agent-codex]='codex'
  MODULE_ALLOW_ALTERNATE_SOURCE[agent-codex]=1

  # Claude Code's verified real source is its own installer script, not
  # @anthropic-ai/claude-code on npm. The installed binary is a symlink into
  # ~/.local/share/claude/versions/, which is what this installer produces.
  MODULE_TITLE[agent-claude-code]='Claude Code'
  MODULE_GROUP[agent-claude-code]='Coding agents'
  MODULE_DEPS[agent-claude-code]='base-packages'
  MODULE_KIND[agent-claude-code]=install-script
  MODULE_URL[agent-claude-code]=$CLAUDE_CODE_INSTALL_URL
  MODULE_INTERPRETER[agent-claude-code]='bash'
  MODULE_BINARY[agent-claude-code]='claude'
  MODULE_COMMANDS[agent-claude-code]='claude'
  MODULE_ALLOW_ALTERNATE_SOURCE[agent-claude-code]=1

  # OpenCode's verified real source is its own installer script, not
  # opencode-ai on npm. The binary lands at ~/.opencode/bin/opencode, not
  # ~/.local/bin, so MODULE_BINARY_PATH overrides the default detection path.
  MODULE_TITLE[agent-opencode]='OpenCode'
  MODULE_GROUP[agent-opencode]='Coding agents'
  MODULE_DEPS[agent-opencode]='base-packages'
  MODULE_KIND[agent-opencode]=install-script
  MODULE_URL[agent-opencode]=$OPENCODE_INSTALL_URL
  MODULE_INTERPRETER[agent-opencode]='bash'
  MODULE_BINARY[agent-opencode]='opencode'
  MODULE_BINARY_PATH[agent-opencode]='$HOME/.opencode/bin/opencode'
  MODULE_COMMANDS[agent-opencode]='opencode'
  MODULE_ALLOW_ALTERNATE_SOURCE[agent-opencode]=1

  # herdr's verified real source is its own installer script, documented to
  # run under `sh`, not `bash`. The npm package named `herdr` is version
  # 0.0.0, a placeholder — it is NOT the real herdr and must not be used.
  MODULE_TITLE[agent-herdr]='herdr'
  MODULE_GROUP[agent-herdr]='Coding agents'
  MODULE_DEPS[agent-herdr]='base-packages'
  MODULE_KIND[agent-herdr]=install-script
  MODULE_URL[agent-herdr]=$HERDR_INSTALL_URL
  MODULE_INTERPRETER[agent-herdr]='sh'
  MODULE_BINARY[agent-herdr]='herdr'
  MODULE_COMMANDS[agent-herdr]='herdr'
  MODULE_ALLOW_ALTERNATE_SOURCE[agent-herdr]=1

  MODULE_TITLE[angular-cli]='Angular CLI'
  MODULE_GROUP[angular-cli]='Developer services'
  MODULE_DEPS[angular-cli]='node-nvm'
  MODULE_KIND[angular-cli]=npm
  MODULE_NPM_PACKAGE[angular-cli]='@angular/cli'
  MODULE_COMMANDS[angular-cli]='ng'
  MODULE_ALLOW_ALTERNATE_SOURCE[angular-cli]=1

  # T8: installs the versioned config/ tree (zsh, zellij, herdr, agent CLI
  # configs) onto $HOME, backing up any existing destination first. Unlike
  # a package module it always re-applies (see module_installed in
  # lib/installer.sh): re-running it is how the host picks up an updated
  # config/ tree, and every run still backs up whatever it replaces.
  MODULE_TITLE[spidy-config]='Spidy versioned configs (zsh, Powerlevel10k, zellij, herdr)'
  MODULE_GROUP[spidy-config]='Configuration'
  MODULE_KIND[spidy-config]=config-tree
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

# The default flow (T3) installs the complete environment: every optional
# module, resolved through the same dependency graph as an explicit
# --modules request. --modules remains the advanced escape hatch for a
# partial install.
default_selected_modules() {
  if [[ -n ${REQUESTED_MODULES:-} ]]; then
    expand_requested_modules "$REQUESTED_MODULES"
  else
    expand_requested_modules all
  fi
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
    git-theme|git-clone)
      printf '  git clone --depth=1 %s %s\n' "${MODULE_URL[$module]}" "${MODULE_PATH[$module]}"
      ;;
    nvm)
      printf "  curl --fail --show-error --location --proto '=https' --tlsv1.2 --retry 3 %s | bash; nvm install --lts\n" "${MODULE_URL[$module]}"
      ;;
    bun|pnpm)
      printf "  curl --fail --show-error --location --proto '=https' --tlsv1.2 --retry 3 %s | bash\n" "${MODULE_URL[$module]}"
      ;;
    rustup)
      printf "  curl --fail --show-error --location --proto '=https' --tlsv1.2 --retry 3 %s | sh -s -- -y\n" "${MODULE_URL[$module]}"
      ;;
    npm)
      printf '  npm install -g %s\n' "${MODULE_NPM_PACKAGE[$module]}"
      ;;
    github-release)
      printf '  curl -L -o archive.tar.gz %s && tar -xzf archive.tar.gz && install -m 0755 %s ~/.local/bin/%s\n' \
        "${MODULE_URL[$module]}" "${MODULE_BINARY[$module]:-$module}" "${MODULE_BINARY[$module]:-$module}"
      ;;
    go-tarball)
      printf '  curl -L %s | tar -C ~/.local -xzf -\n' "$GO_TARBALL_URL"
      ;;
    go-install)
      printf '  ~/.local/go/bin/go install %s\n' "${MODULE_GO_PACKAGE[$module]}"
      ;;
    install-script)
      printf "  curl --fail --show-error --location --proto '=https' --tlsv1.2 --retry 3 %s | %s\n" \
        "${MODULE_URL[$module]}" "${MODULE_INTERPRETER[$module]:-bash}"
      ;;
    guidance)
      printf '  Print Nerd Font installation and terminal-profile guidance.\n'
      ;;
    config-tree)
      printf '  Install the versioned config/ tree onto $HOME (%s), backing up any existing destination file first.\n' \
        "${!CONFIG_FILE_MAP[*]}"
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
