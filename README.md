<div align="center">

<img src="https://github.com/SpidySamurai/SpidySamurai/raw/master/Assets/saludo-spidy.gif" alt="Spidy waving hello" width="180" />

# Spidy's Dev Environment Bootstrap

**A self-contained Bash installer for Javier "Spidy" Chi's curated Ubuntu 24.04 and WSL2 development-tooling baseline.**

The essentials always apply. You choose the optional tools on top of them.

![Ubuntu 24.04](https://img.shields.io/badge/Ubuntu-24.04-E95420?logo=ubuntu&logoColor=white)
![WSL2](https://img.shields.io/badge/WSL2-supported-0078D6?logo=windows&logoColor=white)
![Bash](https://img.shields.io/badge/Bash-installer-4EAA25?logo=gnubash&logoColor=white)

[Why this exists](#why-this-exists) ·
[Quick start](#quick-start) ·
[What it manages](#what-it-manages) ·
[Supported scope](#supported-scope) ·
[Security](#security-and-trust-boundaries) ·
[Architecture](#architecture) ·
[Validation](#validation)

</div>

---

## Why this exists

This is not a universal dotfiles project. It captures the opinionated set of tools I consider most useful for my own machines, so I can rebuild a development environment in minutes instead of repeating a long manual setup. It is published transparently so others can inspect the approach and decide what fits their own workflow.

The scope is intentionally focused on bootstrapping tools rather than managing an entire workstation. Every module is visible before anything runs: the catalog, dependency graph, and shell commands live in plain files in this repository, not behind a black-box installer.

## Quick start

<img src="https://github.com/SpidySamurai/SpidySamurai/raw/master/Assets/work-spidy.gif" alt="Spidy working at a terminal" align="right" width="140" />

Inspect before you install, dry-run before you commit, install only what you choose.

```bash
cd ~/dev-environment-bootstrap

# 1. Audit — read-only. No selection, no network, no host changes.
./install.sh --audit

# 2. Dry-run — opens the interactive selector, resolves the plan, prints
#    the commands it would run. Nothing is installed.
./install.sh --dry-run

# 3. Install — same selector, same plan, but installs only after you confirm it.
./install.sh
```

No optional tool is installed unless you select it, and no installation command runs until you confirm the plan.

Use `./install.sh --help` for the full command reference.

### Fresh machine or remote checkout

```bash
git clone https://github.com/SpidySamurai/dev-environment-bootstrap.git ~/dev-environment-bootstrap
cd ~/dev-environment-bootstrap && ./install.sh
```

Run the audit → dry-run → install sequence above right after cloning.

### Non-interactive and targeted runs

For a known selection, skip the interactive selector entirely. `--non-interactive` installs the mandatory baseline plus only the module IDs you provide; `--yes` accepts the displayed plan without a prompt, so only use it after you've reviewed the selection.

```bash
# Preview a known selection; no commands are executed.
./install.sh --dry-run --non-interactive --modules cli-modern,docker,node-nvm,agent-codex

# Install every optional module after accepting the displayed plan automatically.
./install.sh --non-interactive --modules all

# Install only these optional groups after accepting the displayed plan automatically.
./install.sh --non-interactive --modules multiplexers,go,rust,github-cli
```

## What it manages

### Mandatory baseline

Always applied, cannot be deselected:

- apt metadata update and core prerequisites (`curl`, Git, CA certificates, fonts, and helpers)
- Zsh, Oh My Zsh, Powerlevel10k, and Nerd Font/Windows Terminal guidance
- a guarded minimal Zsh configuration flow

### Optional groups

Select these interactively, or explicitly with `--modules`:

| Module ID | Contents |
| --- | --- |
| `cli-modern` | fzf, zoxide, direnv, bat, eza, ripgrep, fd, delta |
| `multiplexers` | Zellij and tmux |
| `docker` | Docker Engine packages and required apt helpers |
| `node-nvm`, `bun`, `go`, `rust` | Node LTS via nvm, Bun, Go, Rust |
| `github-cli` | GitHub CLI |
| `agent-gentle-ai`, `agent-pi`, `agent-codex`, `agent-claude-code`, `agent-opencode`, `agent-herdr` | Coding-agent CLIs |

Dependencies are data-driven: selecting Docker pulls in its package prerequisites, and selecting an npm-installed agent pulls in `node-nvm`. `--modules all` selects every optional module.

These are the tools I reach for daily. They're not the only good options — swap the catalog entries in `lib/modules.sh` if yours differ.

## Supported scope

- Ubuntu **24.04** on native Linux or WSL2. Unsupported operating systems and Ubuntu releases fail with an actionable error before installation.
- The interactive selector uses [Gum](https://github.com/charmbracelet/gum) only when it's already installed. Otherwise it falls back to a numbered plain-terminal selector; the installer never installs Gum at runtime.
- The installer is idempotent by design: package modules are skipped when their packages are installed, repository/runtime modules check their expected installation path or executable, and configuration files are guarded. `--audit` reuses these read-only checks without strict Ubuntu validation, selection, confirmation, network access, or host mutation.

Docker packages install from Ubuntu's repositories. WSL Docker integration, systemd enablement, and adding a user to the `docker` group remain host-specific manual steps.

### Detection semantics and limits

Command evidence belongs to the module catalog. The audit reports:

- `installed (managed source)` when the module's configured package/path probe succeeds and every declared command is available.
- `installed (alternate source)` when an optional module's complete declared command evidence is available but its configured package/path probe is not.
- Live installation and dry-run plans skip every module reported as installed, regardless of source, rather than reinstalling it.
- `partial (...)` when only some required commands are available, or when a managed installation lacks required command evidence. Partial groups list their missing commands.
- `missing` when neither the configured probe nor any declared command evidence is available.
- `manual/host configuration required` for settings intentionally outside the installer.

Presence means a command is available in `PATH`; it does not validate command versions, package provenance beyond the configured package/path probe, daemon health, provider authentication, authorization, Docker access, or host configuration. Mandatory baseline modules stay conservative: command presence alone never marks them as alternate-source installed or correctly configured.

## Manual configuration

### Shell configuration and fonts

The installer **never overwrites or follows** an existing `~/.zshrc` or `~/.p10k.zsh`, including dangling symbolic links. If `~/.zshrc` is absent and is not a symbolic link, it creates a minimal Oh My Zsh/Powerlevel10k configuration. Otherwise it prints the one theme setting to add manually. Existing Powerlevel10k preferences are preserved.

Nerd Font installation is intentionally guidance-only: install a Nerd Font such as MesloLGS NF in Windows Terminal, then select it for the WSL profile. Windows Terminal profile settings are not modified.

### Authentication, SSH, and Docker host settings

This project never installs secrets, credentials, API keys, SSH keys, or provider authentication. After installation, authenticate manually (for example `gh auth login`) and create/configure SSH keys separately.

WSL Docker integration, systemd enablement, and adding a user to the `docker` group are also manual host-specific steps.

## Security and trust boundaries

The installer resolves and prints the complete plan before it asks for confirmation; no host mutation happens before that confirmation. `--yes` and `--non-interactive` accept the displayed plan without a prompt. Package installation requires `sudo`; all privileged apt commands are centralized in `lib/common.sh` and visible in the dry-run plan. Remote runtime/bootstrap scripts use curl with `--fail --show-error --location --proto '=https' --tlsv1.2 --retry 3`. They require network access and execute only after confirmation and outside `--dry-run`; review their upstream URLs in `lib/modules.sh` before use.

## Architecture

`install.sh` is the orchestration entry point. `lib/modules.sh` contains the declarative module catalog, dependency graph, and dry-run rendering. `lib/ui.sh` owns Gum and terminal selection, `lib/platform.sh` validates Ubuntu/WSL, and `lib/common.sh` centralizes command, network, and privilege behavior. `lib/installer.sh` executes the resolved data-driven plan. Lightweight shell tests live in `tests/` and do not invoke sudo, apt, curl, or interactive installation.

## Validation

```bash
./tests/run.sh
# Optional when installed:
shellcheck install.sh lib/*.sh tests/*.sh
```

## License

No license file is published yet, so no reuse rights are granted beyond viewing the source. If you want to build on this, ask first.

<div align="center">
<img src="https://github.com/SpidySamurai/SpidySamurai/raw/master/Assets/good-spidy.gif" alt="Spidy giving a thumbs up" width="140" />
</div>
