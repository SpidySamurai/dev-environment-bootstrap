#!/usr/bin/env bash
# spidy-environment one-liner bootstrap.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/SpidySamurai/dev-environment-bootstrap/main/bootstrap.sh | bash
#
# This script is designed to run through a pipe, so stdin is the script
# itself: it never reads from stdin and it is fully non-interactive. It
# verifies the host, clones (or updates) the repository checkout, installs a
# `spidy-environment` launcher on PATH, and prints the next command to run.
#
# Every function below is testable in isolation: this file can be sourced
# (tests/test_bootstrap.sh does exactly that) without triggering `main`,
# because of the sourced-or-executed guard at the bottom of the file.

# Overridable so a smoke test can bootstrap from a local clone instead of
# reaching GitHub. Defaults to the real repository.
BOOTSTRAP_REPO_URL=${BOOTSTRAP_REPO_URL:-'https://github.com/SpidySamurai/dev-environment-bootstrap.git'}

# Overridable only for tests; defaults to the real system file.
BOOTSTRAP_OS_RELEASE_FILE=${BOOTSTRAP_OS_RELEASE_FILE:-/etc/os-release}

# Verifies the host the same way lib/platform.sh's validate_host does
# (Ubuntu 24.04 on Linux), but standalone: at bootstrap time the repository
# has not been cloned yet, so lib/platform.sh is not available to source.
bootstrap_validate_host() {
  if [[ $(uname -s) != Linux ]]; then
    printf '%s\n' 'Unsupported host: this installer requires Linux (Ubuntu 24.04 on WSL2 is supported).' >&2
    return 1
  fi
  if [[ ! -r "$BOOTSTRAP_OS_RELEASE_FILE" ]]; then
    printf '%s\n' 'Unsupported host: /etc/os-release is unavailable; Ubuntu 24.04 is required.' >&2
    return 1
  fi

  local ID='' VERSION_ID=''
  # /etc/os-release is the operating-system metadata format defined by systemd.
  # shellcheck disable=SC1090
  . "$BOOTSTRAP_OS_RELEASE_FILE"
  if [[ $ID != ubuntu || $VERSION_ID != 24.04 ]]; then
    printf 'Unsupported host: detected %s %s; this bootstrap supports Ubuntu 24.04 only.\n' "${ID:-unknown}" "${VERSION_ID:-unknown}" >&2
    return 1
  fi
  return 0
}

# Isolated so tests can override `sudo` without a real privileged step.
bootstrap_apt_install_git() {
  sudo apt-get update && sudo apt-get install -y git
}

# Ensures git and curl exist. curl is required to fetch this very script in
# the primary one-liner flow, so a missing curl means an unsupported
# transport was used to run it; git is installed via apt when missing, since
# that is the one privileged step this bootstrap performs.
bootstrap_ensure_git_curl() {
  if ! command -v curl >/dev/null 2>&1; then
    printf 'curl is required but was not found. Install curl and re-run this script.\n' >&2
    return 1
  fi

  if command -v git >/dev/null 2>&1; then
    return 0
  fi

  if ! command -v sudo >/dev/null 2>&1; then
    printf 'git is required but was not found, and sudo is unavailable to install it automatically. Install git manually and re-run this script.\n' >&2
    return 1
  fi

  printf 'git was not found; installing it via apt (this is the one privileged step this bootstrap performs)...\n' >&2
  if ! bootstrap_apt_install_git; then
    printf 'Failed to install git automatically. Install git manually and re-run this script.\n' >&2
    return 1
  fi
}

# The checkout location, derived entirely from $HOME/$XDG_DATA_HOME so
# nothing assumes a fixed username or home directory.
bootstrap_checkout_dir() {
  printf '%s/spidy-environment' "${XDG_DATA_HOME:-$HOME/.local/share}"
}

# Clones the repository into the checkout directory, or fast-forwards it if
# a checkout already exists there.
bootstrap_ensure_checkout() {
  local checkout_dir
  checkout_dir=$(bootstrap_checkout_dir)

  if [[ -d "$checkout_dir/.git" ]]; then
    printf 'Updating existing checkout at %s...\n' "$checkout_dir" >&2
    git -C "$checkout_dir" pull --ff-only
    return $?
  fi

  printf 'Cloning %s into %s...\n' "$BOOTSTRAP_REPO_URL" "$checkout_dir" >&2
  mkdir -p "$(dirname "$checkout_dir")"
  git clone "$BOOTSTRAP_REPO_URL" "$checkout_dir"
}

# Installs a launcher at $HOME/.local/bin/spidy-environment that execs the
# checkout's install.sh, forwarding all arguments. The checkout path is
# resolved here, at install time, and baked into the generated launcher
# rather than re-derived (and possibly guessed wrong) on every invocation.
bootstrap_install_launcher() {
  local checkout_dir launcher_dir launcher_path
  checkout_dir=$(bootstrap_checkout_dir)
  launcher_dir="$HOME/.local/bin"
  launcher_path="$launcher_dir/spidy-environment"

  mkdir -p "$launcher_dir"
  cat >"$launcher_path" <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec "$checkout_dir/install.sh" "\$@"
EOF
  chmod +x "$launcher_path"
  printf 'Installed launcher: %s\n' "$launcher_path" >&2
}

bootstrap_path_contains_local_bin() {
  case ":${PATH:-}:" in
    *":$HOME/.local/bin:"*) return 0 ;;
    *) return 1 ;;
  esac
}

# Picks the rc file matching the user's current shell so the PATH change
# takes effect the next time they open a terminal.
bootstrap_shell_rc_file() {
  case "${SHELL:-}" in
    */zsh) printf '%s/.zshrc' "$HOME" ;;
    *) printf '%s/.bashrc' "$HOME" ;;
  esac
}

# Ensures $HOME/.local/bin is on PATH. If it already is, this is a no-op. If
# it is not, the export line is appended to the shell rc file exactly once,
# and the change is reported explicitly (it cannot take effect in the
# current, already-running shell that piped this script into bash).
bootstrap_ensure_path() {
  if bootstrap_path_contains_local_bin; then
    return 0
  fi

  local rc_file line
  rc_file=$(bootstrap_shell_rc_file)
  # Written literally so the shell expands it at login, not now.
  # shellcheck disable=SC2016
  line='export PATH="$HOME/.local/bin:$PATH"'

  if [[ -f "$rc_file" ]] && grep -qF "$line" "$rc_file" 2>/dev/null; then
    printf '%s already adds ~/.local/bin to PATH; restart your shell to pick it up.\n' "$rc_file" >&2
    return 0
  fi

  {
    printf '\n# Added by the spidy-environment bootstrap\n'
    printf '%s\n' "$line"
  } >>"$rc_file"
  printf 'Added ~/.local/bin to PATH in %s. Restart your shell (or run: source %s) before using spidy-environment.\n' "$rc_file" "$rc_file" >&2
}

main() {
  set -euo pipefail

  bootstrap_validate_host
  bootstrap_ensure_git_curl
  bootstrap_ensure_checkout
  bootstrap_install_launcher
  bootstrap_ensure_path

  cat <<'EOF'

Bootstrap complete. Authentication, API keys, provider login, and SSH keys
are still manual. Run:

  spidy-environment

EOF
}

# Runs main only when this file is executed (directly, or piped into bash),
# never when it is sourced — tests/test_bootstrap.sh sources this file to
# exercise its functions in isolation. `(return 0 2>/dev/null)` only
# succeeds when we are inside a sourced script.
if ! (return 0 2>/dev/null); then
  main "$@"
fi
