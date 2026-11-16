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
[Configuration](#configuration) ·
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

One line, then one command. On a fresh Ubuntu 24.04 machine (native or WSL2):

```bash
curl -fsSL https://raw.githubusercontent.com/SpidySamurai/dev-environment-bootstrap/master/bootstrap.sh | bash
```

`bootstrap.sh` verifies the host, clones this repository into
`${XDG_DATA_HOME:-$HOME/.local/share}/spidy-environment` (or fast-forwards it if
it is already there), and installs a `spidy-environment` launcher on your
`PATH`. It is fully non-interactive: it never reads from stdin, since stdin is
the piped script itself.

Once it prints its final line, run:

```bash
spidy-environment
```

That opens the plan and a single yes/no confirmation
(`Install the complete Spidy environment? [Y/n]`), then installs everything:
tools and configs (see [Configuration](#configuration)). No multi-select
menu, and a single module failing never aborts the rest of the run — you get
a full report of what succeeded, what was skipped, and what failed and why.

Re-running `curl ... | bash` later just fast-forwards the checkout, and
`spidy-environment` accepts every flag `install.sh` does (see below), since it
simply execs the checkout's `install.sh`.

### Advanced: `--dry-run`, `--audit`, `--yes`, `--non-interactive`, `--modules`

Inspect before you install, dry-run before you commit, install only what you choose.

```bash
# Audit — read-only. No selection, no network, no host changes.
spidy-environment --audit

# Dry-run — resolves the plan and prints the commands it would run. Nothing
# is installed.
spidy-environment --dry-run

# Skip the yes/no prompt once you've reviewed the plan.
spidy-environment --yes

# Non-interactive: no prompts at all (implies --yes); use --modules to pick a
# partial install instead of the default complete environment.
spidy-environment --non-interactive --modules cli-modern,docker,node-nvm,agent-codex
spidy-environment --non-interactive --modules all
```

Use `spidy-environment --help` (or `./install.sh --help` from a checkout) for
the full command reference.

### Working from a local checkout

If you already have the repository checked out (for example, to edit the
catalog), run it directly instead of through the launcher:

```bash
cd ~/dev-environment-bootstrap
./install.sh --audit
./install.sh --dry-run
./install.sh
```

## What it manages

### Mandatory baseline

Always applied, cannot be deselected:

- apt metadata update and core prerequisites (`curl`, Git, CA certificates, fonts, and helpers)
- Zsh, Oh My Zsh, Powerlevel10k, and Nerd Font/Windows Terminal guidance
- a guarded minimal Zsh configuration flow

### Optional groups

All are selected by default (the complete-environment flow); narrow the selection explicitly with `--modules`:

| Module ID | Contents |
| --- | --- |
| `cli-modern` | fzf, zoxide, direnv, bat, eza, ripgrep, fd, delta |
| `tmux`, `zellij` | tmux (apt) and Zellij (upstream release binary) |
| `docker` | Docker Engine packages and required apt helpers |
| `node-nvm`, `bun`, `pnpm`, `go`, `rust` | Node LTS via nvm, Bun, pnpm, Go, Rust |
| `lazygit` | Terminal Git UI (via `go install`, depends on `go`) |
| `github-cli` | GitHub CLI |
| `angular-cli` | Angular CLI (`ng`, via nvm's global npm) |
| `zsh-autosuggestions`, `zsh-syntax-highlighting` | Oh My Zsh custom plugins |
| `agent-gentle-ai`, `agent-pi`, `agent-codex`, `agent-claude-code`, `agent-opencode`, `agent-herdr` | Coding-agent CLIs |
| `spidy-config` | The versioned `config/` tree (see [Configuration](#configuration) below) |

Dependencies are data-driven: selecting Docker pulls in its package prerequisites, and selecting an npm-installed agent pulls in `node-nvm`. `--modules all` (the default, complete-environment flow) selects every optional module, including `spidy-config`.

These are the tools I reach for daily. They're not the only good options — swap the catalog entries in `lib/modules.sh` if yours differ.

## Configuration

By default (the `spidy-config` module, selected like any other optional module), the installer also places my versioned shell and terminal dotfiles on the host:

| Source | Destination |
| --- | --- |
| `config/zsh/zshrc` | `~/.zshrc` |
| `config/zsh/p10k.zsh` | `~/.p10k.zsh` |
| `config/zellij/config.kdl` | `~/.config/zellij/config.kdl` |
| `config/herdr/config.toml` | `~/.config/herdr/config.toml` |

Any file already at one of those destinations is backed up first, to `<file>.bak.<UTC timestamp>` — nothing is silently overwritten. Because this module re-applies the versioned tree, re-running it (for example after a `git pull` picks up a config update) creates a fresh backup each time.

**Authentication stays manual.** This module never installs secrets: no API keys, no provider login, no SSH keys. Run `gh auth login`, each agent CLI's own login command, and set up SSH keys yourself, same as always.

**`~/.zshrc.local` is yours.** The shipped `.zshrc` sources `~/.zshrc.local` if it exists and is never versioned — put secrets, work-specific identities, and machine-specific settings there.

Deselect `spidy-config` (`--modules` without it) to skip all of this and fall back to the built-in guarded minimal Zsh configuration described in [Shell configuration and fonts](#shell-configuration-and-fonts).

## Supported scope

- Ubuntu **24.04** on native Linux or WSL2. Unsupported operating systems and Ubuntu releases fail with an actionable error before installation — both `bootstrap.sh` and `install.sh` check this.
- The default flow is a single yes/no confirmation (no interactive menu): the plan is resolved and printed first, then one prompt confirms installing it. `--modules` remains the advanced escape hatch for a partial install.
- The installer is idempotent by design: package modules are skipped when their packages are installed, repository/runtime modules check their expected installation path or executable, and configuration files are guarded. `--audit` reuses these read-only checks without strict Ubuntu validation, selection, confirmation, network access, or host mutation. The `spidy-config` module is the one exception: it always re-applies (see [Configuration](#configuration)).

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

By default the `spidy-config` module (see [Configuration](#configuration)) installs the full `~/.zshrc` and `~/.p10k.zsh`, backing up whatever was there first. If you deselect `spidy-config`, the installer falls back to a guarded minimal flow: it **never overwrites or follows** an existing `~/.zshrc` or `~/.p10k.zsh`, including dangling symbolic links. If `~/.zshrc` is absent and is not a symbolic link, it creates a minimal Oh My Zsh/Powerlevel10k configuration; otherwise it prints the one theme setting to add manually. Existing Powerlevel10k preferences are preserved either way.

Nerd Font installation is intentionally guidance-only: install a Nerd Font such as MesloLGS NF in Windows Terminal, then select it for the WSL profile. Windows Terminal profile settings are not modified.

### Authentication, SSH, and Docker host settings

This project never installs secrets, credentials, API keys, SSH keys, or provider authentication. After installation, authenticate manually (for example `gh auth login`) and create/configure SSH keys separately.

WSL Docker integration, systemd enablement, and adding a user to the `docker` group are also manual host-specific steps.

## Security and trust boundaries

`bootstrap.sh` performs exactly one privileged step before anything else runs: installing `git` via apt, and only if it is missing. From there, `install.sh` resolves and prints the complete plan before it asks for confirmation; no host mutation happens before that confirmation. `--yes` and `--non-interactive` accept the displayed plan without a prompt. Package installation requires `sudo`, negotiated once up front by `lib/privileges.sh`; all privileged apt commands are centralized in `lib/common.sh` and visible in the dry-run plan. Remote runtime/bootstrap scripts use curl with `--fail --show-error --location --proto '=https' --tlsv1.2 --retry 3`. They require network access and execute only after confirmation and outside `--dry-run`; review their upstream URLs in `lib/modules.sh` before use.

## Architecture

`bootstrap.sh` is the one-liner entry point: it verifies the host, clones or updates the checkout, and installs the `spidy-environment` launcher, which execs the checkout's `install.sh`. `install.sh` is the orchestration entry point from there on. `lib/modules.sh` contains the declarative module catalog, dependency graph, and dry-run rendering. `lib/config.sh` installs the versioned `config/` tree with backups and `__SPIDY_HOME__` substitution. `lib/ui.sh` owns the single yes/no confirmation, `lib/platform.sh` validates Ubuntu/WSL, `lib/privileges.sh` negotiates `sudo` once up front, and `lib/common.sh` centralizes command, network, and privilege behavior. `lib/installer.sh` executes the resolved data-driven plan, isolating each module's failures so one failing module never aborts the rest. Lightweight shell tests live in `tests/` and do not invoke sudo, apt, curl, or real network access.

## Validation

```bash
./tests/run.sh
# Optional when installed:
shellcheck install.sh bootstrap.sh lib/*.sh tests/*.sh
```

## License

No license file is published yet, so no reuse rights are granted beyond viewing the source. If you want to build on this, ask first.

<div align="center">
<img src="https://github.com/SpidySamurai/SpidySamurai/raw/master/Assets/good-spidy.gif" alt="Spidy giving a thumbs up" width="140" />
</div>
