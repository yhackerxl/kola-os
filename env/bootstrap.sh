#!/usr/bin/env bash
# One-time creation of the isolated Debian 12 build root.
# No Docker: plain debootstrap/mmdebstrap rootfs, host is never modified.
set -euo pipefail

ROOT="${KOLA_BUILDROOT:-$HOME/.cache/kola-buildroot}"
SUITE=bookworm
MIRROR=http://deb.debian.org/debian

[ "$(id -u)" -eq 0 ] || exec sudo -E "$0" "$@"

apt-get update
apt-get install -y --no-install-recommends mmdebstrap qemu-system-x86 ovmf

if [ -d "${ROOT}/etc" ]; then
	echo ">> build root already exists: ${ROOT}"
	exit 0
fi

mkdir -p "$(dirname "${ROOT}")"

mmdebstrap \
	--variant=apt \
	--include=live-build,ca-certificates,genisoimage,console-setup,locales \
	"${SUITE}" "${ROOT}" "${MIRROR}"

echo ">> build root ready: ${ROOT}"
