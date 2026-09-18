#!/usr/bin/env bash
# Launches a throwaway Ubuntu 24.04 container prepared to try this installer by
# hand, and drops you into a shell as an unprivileged user with sudo.
#
#   ./tests/try-in-docker.sh
#
# The container installs from a snapshot of your CURRENT working tree, including
# uncommitted changes, so you test what you have rather than what is on GitHub.
# Nothing touches your host: the repository is mounted read-only and the
# container is deleted on exit.
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
IMAGE=${SPIDY_TRY_IMAGE:-ubuntu:24.04}

# Docker on WSL2 frequently has no working DNS in containers, which makes
# apt fail with "Temporary failure resolving archive.ubuntu.com" while still
# exiting 0. Pinning a resolver avoids a confusing half-broken machine.
DNS_ARGS=()
[[ -n ${SPIDY_TRY_DNS:-8.8.8.8} ]] && DNS_ARGS=(--dns "${SPIDY_TRY_DNS:-8.8.8.8}")

setup=$(cat <<'INNER'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
echo "==> preparing a clean Ubuntu 24.04 machine"
apt-get update -qq
apt-get install -y -qq sudo ca-certificates curl git

useradd -m -s /bin/bash tester
echo 'tester ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/tester
chmod 0440 /etc/sudoers.d/tester

echo "==> snapshotting your working tree (uncommitted changes included)"
cp -r /src /tmp/repo-src
cd /tmp/repo-src
rm -rf .codegraph .atl
git config --global --add safe.directory /tmp/repo-src
git -c user.email=try@local -c user.name=try add -A >/dev/null
git -c user.email=try@local -c user.name=try commit -qm "local snapshot" >/dev/null || true
chown -R tester:tester /tmp/repo-src

echo "==> running the bootstrap for you, so the launcher is ready on arrival"
sudo -u tester env BOOTSTRAP_REPO_URL=/tmp/repo-src HOME=/home/tester \
  bash /tmp/repo-src/bootstrap.sh

cat >/home/tester/TRY-ME <<'HELP'
The bootstrap already ran. spidy-environment is on your PATH.

  spidy-environment              <- the panel and the single yes/no
  spidy-environment --dry-run    <- same panel, installs nothing
  spidy-environment --audit      <- read-only inventory

After installing, poke at what landed:

  cat ~/.zshrc
  ls ~/.claude ~/.codex ~/.config/zellij
  zsh

Nothing here touches your real machine. Type exit to destroy the container.
HELP
chown tester:tester /home/tester/TRY-ME
INNER
)

printf '==> starting %s (this takes a minute the first time)\n' "$IMAGE" >&2
exec docker run --rm -it "${DNS_ARGS[@]}" \
  -v "$ROOT_DIR":/src:ro \
  "$IMAGE" \
  bash -c "$setup"'; echo; cat /home/tester/TRY-ME; echo; exec su - tester -c 'export PATH="$HOME/.local/bin:$PATH"; exec bash -i''
