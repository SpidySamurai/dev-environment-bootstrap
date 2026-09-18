#!/usr/bin/env bash
# Creates a throwaway WSL2 distribution to try this installer on the real target
# platform, then tells you how to enter it and how to delete it.
#
#   ./tests/try-in-wsl.sh
#
# Docker is used only to obtain a clean Ubuntu 24.04 root filesystem; the thing
# you end up testing in is a genuine WSL distribution, not a container. The
# installer is exercised against a snapshot of your CURRENT working tree,
# including uncommitted changes.
#
# Your real distribution is never touched. To remove the test one:
#   wsl.exe --unregister spidy-test
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DISTRO=${SPIDY_TEST_DISTRO:-spidy-test}
STAGING_LINUX=/mnt/c/spidy-wsl-test
STAGING_WIN='C:\spidy-wsl-test'
TEST_USER=spidy

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

command -v docker >/dev/null 2>&1 || die 'docker is required to export a clean Ubuntu 24.04 root filesystem.'
command -v wsl.exe >/dev/null 2>&1 || die 'wsl.exe was not found; this script must run inside WSL.'

if wsl.exe -l -q 2>/dev/null | tr -d '\0\r' | grep -qx "$DISTRO"; then
  die "a distribution named '$DISTRO' already exists. Remove it first: wsl.exe --unregister $DISTRO"
fi

printf '==> exporting a clean Ubuntu 24.04 root filesystem\n' >&2
mkdir -p "$STAGING_LINUX"
container=$(docker create ubuntu:24.04 /bin/true)
trap 'docker rm -f "$container" >/dev/null 2>&1 || true' EXIT
docker export "$container" -o "$STAGING_LINUX/rootfs.tar"

printf '==> staging a snapshot of your working tree (uncommitted changes included)\n' >&2
rm -rf "$STAGING_LINUX/repo"
mkdir -p "$STAGING_LINUX/repo"
# Excluded DURING the copy, not after: .codegraph holds a unix socket and the
# Windows filesystem cannot represent one, so a plain cp -r aborts on it.
tar -cf - -C "$ROOT_DIR" --exclude=./.codegraph --exclude=./.atl . \
  | tar -xf - -C "$STAGING_LINUX/repo"
git -C "$STAGING_LINUX/repo" config --local user.email try@local
git -C "$STAGING_LINUX/repo" config --local user.name try
git -C "$STAGING_LINUX/repo" add -A >/dev/null
git -C "$STAGING_LINUX/repo" commit -qm 'local snapshot' >/dev/null || true

printf '==> importing it as the WSL distribution "%s"\n' "$DISTRO" >&2
wsl.exe --import "$DISTRO" "$STAGING_WIN\\distro" "$STAGING_WIN\\rootfs.tar" >/dev/null

printf '==> preparing the machine (user, sudo, git)\n' >&2
wsl.exe -d "$DISTRO" -u root -- bash -lc "
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq sudo ca-certificates curl git
id -u $TEST_USER >/dev/null 2>&1 || useradd -m -s /bin/bash $TEST_USER
echo '$TEST_USER ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/$TEST_USER
chmod 0440 /etc/sudoers.d/$TEST_USER
printf '[user]\ndefault=$TEST_USER\n[boot]\nsystemd=true\n' >/etc/wsl.conf
cp -r /mnt/c/spidy-wsl-test/repo /home/$TEST_USER/bootstrap-src
chown -R $TEST_USER:$TEST_USER /home/$TEST_USER/bootstrap-src
"

printf '==> running the bootstrap so the launcher is ready when you enter\n' >&2
wsl.exe -d "$DISTRO" -u "$TEST_USER" -- bash -lc "
BOOTSTRAP_REPO_URL=\$HOME/bootstrap-src bash \$HOME/bootstrap-src/bootstrap.sh
"

wsl.exe --terminate "$DISTRO" >/dev/null 2>&1 || true

cat >&2 <<EOF

Ready. Enter the test distribution with:

    wsl.exe -d $DISTRO

Inside it:

    spidy-environment              the panel and the single yes/no
    spidy-environment --dry-run    same panel, installs nothing
    spidy-environment --audit      read-only inventory

When you are done, delete it completely:

    wsl.exe --unregister $DISTRO
    rm -rf $STAGING_LINUX

Your own distribution was not touched.
EOF
