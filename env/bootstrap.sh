#!/usr/bin/env bash
# Provision the shared Debian 12 live-build root.
#
# GLOBAL / REUSABLE: the root lives outside this repo and is shared by every
# project. A new project just points KOLA_BUILDROOT at it (default below) and
# reuses the same live-build toolchain - no reinstall, no host pollution.
#
# Usage:
#   ./env/bootstrap.sh                     # install host tools + build root
#   KOLA_BUILDROOT=~/images/lb ./env/bootstrap.sh
set -euo pipefail

ROOT="${KOLA_BUILDROOT:-$HOME/.cache/debian12-live-build}"
SUITE="${KOLA_SUITE:-bookworm}"
MIRROR="${KOLA_MIRROR:-http://deb.debian.org/debian}"

HOST_PKGS=(mmdebstrap debootstrap qemu-system-x86 ovmf)

# Everything live-build needs. The chroot uses --variant=apt, so recommends are
# NOT pulled automatically; this list must stay explicit.
CHROOT_PKGS=(
	live-build
	debootstrap
	squashfs-tools
	xorriso
	genisoimage
	mtools
	dosfstools
	grub-efi-amd64-bin
	grub-pc-bin
	syslinux-common
	isolinux
	ca-certificates
	locales
	console-setup
	file
	less
)

[ "$(id -u)" -eq 0 ] || exec sudo -E "$0" "$@"

echo ">> host packages"
apt-get update
apt-get install -y --no-install-recommends "${HOST_PKGS[@]}"

if [ -n "${SUDO_USER:-}" ] && ! id -nG "${SUDO_USER}" | tr ' ' '\n' | grep -qx kvm; then
	usermod -aG kvm "${SUDO_USER}"
	echo ">> ${SUDO_USER} added to group kvm (log out/in before QEMU KVM acceleration works)"
fi

if [ -d "${ROOT}/etc" ]; then
	echo ">> reusing existing build root: ${ROOT}"
else
	echo ">> creating build root: ${ROOT}"
	mkdir -p "$(dirname "${ROOT}")"
	mmdebstrap \
		--variant=apt \
		--include="$(IFS=,; echo "${CHROOT_PKGS[*]}")" \
		"${SUITE}" "${ROOT}" "${MIRROR}"
fi

echo ">> verifying chroot packages"
missing=0
for p in "${CHROOT_PKGS[@]}"; do
	if ! chroot "${ROOT}" dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q "install ok installed"; then
		echo "   MISSING: $p"
		missing=1
	fi
done

if [ "${missing}" -ne 0 ]; then
	echo "ERROR: build root incomplete - install the missing packages inside ${ROOT}" >&2
	exit 1
fi

echo ">> build root ready: ${ROOT}"
