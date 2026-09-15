# WSL/Ubuntu Developer Environment Bootstrap

A self-contained Bash installer for a reproducible Ubuntu 24.04 developer baseline, including WSL2. It always includes the mandatory baseline and lets you select optional developer tooling interactively. It resolves dependencies, shows the final plan, and waits for confirmation before changing the host.

## Install from this checkout

```bash
cd ~/dev-environment-bootstrap && ./install.sh
```

This is the full interactive install: choose any optional modules, review the resolved plan, and confirm it. No optional tool is installed unless you select it, and no installation command runs until you confirm the plan.

## Safe first run

Use this path to inspect the machine, preview your interactive choices, then install them:

1. **Audit the current environment** — reports the status of mandatory and optional modules without selection, confirmation, network access, or host changes.

   ```bash
   cd ~/dev-environment-bootstrap && ./install.sh --audit
   ```

2. **Preview an interactive selection** — opens the optional-module selector, resolves the plan, and prints the commands it would run. `--dry-run` does not install anything and never asks for installation confirmation.

   ```bash
   cd ~/dev-environment-bootstrap && ./install.sh --dry-run
   ```

3. **Run the full interactive install** — opens the same selector, displays the plan, then installs only after you confirm it.

   ```bash
   cd ~/dev-environment-bootstrap && ./install.sh
   ```

Use `./install.sh --help` for the full command reference.

## Fresh machine or remote checkout

First publish this repository somewhere accessible. Then replace `<repository-url>` with that published repository's clone URL:

```bash
git clone <repository-url> ~/dev-environment-bootstrap
cd ~/dev-environment-bootstrap && ./install.sh
```

For a safe first run on the fresh machine, use the audit, interactive dry-run, and interactive install sequence above after cloning.

## Non-interactive and targeted runs

The commands below are for a known selection. They do not open the interactive selector; `--non-interactive` installs the mandatory baseline plus only the optional module IDs you provide. `--yes` accepts the displayed plan without a prompt, so use it only after you have reviewed the selected modules.

```bash
# Preview a known selection; no commands are executed.
./install.sh --dry-run --non-interactive --modules cli-modern,docker,node-nvm,agent-codex

# Install every optional module after accepting the displayed plan automatically.
./install.sh --non-interactive --modules all

# Install only these optional groups after accepting the displayed plan automatically.
./install.sh --non-interactive --modules multiplexers,go,rust,github-cli
```

## Supported scope

- Ubuntu **24.04** on native Linux or WSL2. Unsupported operating systems and Ubuntu releases fail with an actionable error before installation.
- The interactive selector uses [Gum](https://github.com/charmbracelet/gum) only when it is already installed. Otherwise, it uses a numbered plain-terminal selector; the installer never installs Gum at runtime.
- The installer is idempotent by design: package modules are skipped when their packages are installed, repository/runtime modules check their expected installation path or executable, and configuration files are guarded. `--audit` reuses read-only checks without strict Ubuntu validation, selection, confirmation, network access, or host mutation.

Docker packages are installed from Ubuntu's repositories. WSL Docker integration, systemd enablement, and adding a user to the `docker` group remain host-specific manual steps.

### Detection semantics and limits

Command evidence belongs to the module catalog. The audit reports:

- `installed (managed source)` when the module's configured package/path probe succeeds and every declared command is available.
- `installed (alternate source)` when an optional module's complete declared command evidence is available but its configured package/path probe is not.
- Live installation and dry-run plans skip every module reported as installed, regardless of source, rather than reinstalling it.
- `partial (...)` when only some required commands are available, or when a managed installation lacks required command evidence. Partial groups list their missing commands.
- `missing` when neither the configured probe nor any declared command evidence is available.
- `manual/host configuration required` for settings intentionally outside the installer.

Presence means a command is available in `PATH`; it does not validate command versions, package provenance beyond the configured package/path probe, daemon health, provider authentication, authorization, Docker access, or host configuration. Mandatory baseline modules remain conservative: command presence alone never marks them as alternate-source installed or correctly configured.

## What the installer manages

### Mandatory baseline

The mandatory baseline cannot be deselected:

- apt metadata update and core prerequisites (`curl`, Git, CA certificates, fonts, and helpers)
- Zsh, Oh My Zsh, Powerlevel10k, and Nerd Font/Windows Terminal guidance
- a guarded minimal Zsh configuration flow

### Optional groups

Select these interactively or explicitly with `--modules`:

| Module ID | Contents |
| --- | --- |
| `cli-modern` | fzf, zoxide, direnv, bat, eza, ripgrep, fd, delta |
| `multiplexers` | Zellij and tmux |
| `docker` | Docker Engine packages and required apt helpers |
| `node-nvm`, `bun`, `go`, `rust` | Node LTS via nvm, Bun, Go, Rust |
| `github-cli` | GitHub CLI |
| `agent-gentle-ai`, `agent-pi`, `agent-codex`, `agent-claude-code`, `agent-opencode`, `agent-herdr` | Coding-agent CLIs |

Dependencies are data-driven. For example, selecting Docker includes its package prerequisites, and selecting an npm-installed agent includes `node-nvm`. `--modules all` selects every optional module.

## Manual configuration

### Shell configuration and fonts

The installer **never overwrites or follows** an existing `~/.zshrc` or `~/.p10k.zsh`, including dangling symbolic links. If `~/.zshrc` is absent and is not a symbolic link, it creates a minimal Oh My Zsh/Powerlevel10k configuration. Otherwise, it prints the one theme setting to add manually. Existing Powerlevel10k preferences are preserved.

Nerd Font installation is intentionally guidance-only: install a Nerd Font such as MesloLGS NF in Windows Terminal, then select it for the WSL profile. Windows Terminal profile settings are not modified.

### Authentication, SSH, and Docker host settings

This project never installs secrets, credentials, API keys, SSH keys, or provider authentication. After installation, authenticate manually (for example `gh auth login`) and create/configure SSH keys separately.

WSL Docker integration, systemd enablement, and adding a user to the `docker` group are also manual host-specific steps.

## Security and network boundary

The installer resolves and prints the complete plan before it asks for confirmation; no host mutation occurs before that confirmation. `--yes` and `--non-interactive` accept the displayed plan without a prompt. Package installation requires `sudo`; all privileged apt commands are centralized in `lib/common.sh` and visible in the dry-run plan. Remote runtime/bootstrap scripts use curl with `--fail --show-error --location --proto '=https' --tlsv1.2 --retry 3`. They require network access and execute only after confirmation and outside `--dry-run`; review their upstream URLs in `lib/modules.sh` before use.

## Architecture

`install.sh` is the orchestration entry point. `lib/modules.sh` contains the declarative module catalog, dependency graph, and dry-run rendering. `lib/ui.sh` owns Gum and terminal selection, `lib/platform.sh` validates Ubuntu/WSL, and `lib/common.sh` centralizes command, network, and privilege behavior. `lib/installer.sh` executes the resolved data-driven plan. Lightweight shell tests live in `tests/` and do not invoke sudo, apt, curl, or interactive installation.

## Validation

```bash
./tests/run.sh
# Optional when installed:
shellcheck install.sh lib/*.sh tests/*.sh
```
