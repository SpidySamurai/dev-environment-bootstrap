# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

First tagged release, planned as v1.0.0. It covers all work since the first
commit in September 2026.

### Added

- Ubuntu 24.04 and WSL2 installer with a declarative module catalog, dependency
  resolution, `--dry-run`, `--audit`, `--yes`, `--non-interactive` and `--modules`.
- `bootstrap.sh` one-liner that checks the host, clones or updates the checkout
  and installs the `spidy-environment` launcher.
- One-time `sudo` negotiation, a single yes/no confirmation read from `/dev/tty`,
  and per-module isolation with a final ok, failed, skipped and manual report.
- Versioned zsh, Powerlevel10k, Zellij and herdr configuration (`spidy-config`),
  with timestamped backups of any file it replaces.
- Coding-agent CLI modules: gentle-ai, Pi, Codex, Claude Code, OpenCode and herdr.
- `tests/try-in-docker.sh` and `tests/try-in-wsl.sh` throwaway sandboxes.
- GitHub Actions CI running ShellCheck v0.11.0 and the test suite.
- MIT license.

### Changed

- Zellij installs a pinned release (v0.46.0) instead of `releases/latest`.
- Go installs from the official tarball, and the agent CLIs from their vendors'
  install scripts, instead of outdated or missing apt and npm packages.
- The README is rewritten around what the installer does and how to run it.

### Removed

- **Breaking:** `spidy-config` no longer installs any coding-agent configuration
  into `~/.claude`, `~/.codex`, `~/.config/opencode` or `~/.pi`. Agents are
  configured with [gentle-ai](https://github.com/Gentleman-Programming/gentle-ai).

### Fixed

- The legacy Zsh step no longer contradicts the shipped `.zshrc` after
  `spidy-config` installs it.
- rustup flags reach the installer instead of being passed to `env`, which made
  the `rust` module fail.
- `tests/try-in-docker.sh` opens the tester shell instead of exiting early.
- The audit test checks a real temporary HOME, and the dry-run test no longer
  depends on Pi being installed on the machine running it.
- ShellCheck findings, including a `local` declaration that read a variable
  before assigning it.
