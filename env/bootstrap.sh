#!/usr/bin/env bash
# Provision the shared Debian 12 live-build root.
#
# GLOBAL / REUSABLE: the root lives outside this repo and is shared by every
# project. A new project just points KOLA_BUILDROOT at it (default below) and
# reuses the same live-build toolchain - no reinstall, no host pollution.
#
# Self-healing:
#   - incomplete root (no /bin/bash) -> moved aside, recreated
#   - valid root, missing packages   -> repaired with apt inside the chroot
set -euo pipefail

ROOT="${KOLA_BUILDROOT:-$HOME/.cache/debian12-live-build}"
SUITE="${KOLA_SUITE:-bookworm}"
MIRROR="${KOLA_MIRROR:-http://deb.debian.org/debian}"

HOST_PKGS=(mmdebstrap debootstrap qemu-system-x86 ovmf debian-archive-keyring)
DEBIAN_KEYRING=/usr/share/keyrings/debian-archive-keyring.gpg

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
	debian-archive-keyring
	# --variant=apt omits Priority: required, and live-build declares only
	# `debootstrap` as a dependency. These are runtime requirements of its scripts.
	mount
	util-linux
	rsync
	cpio
	xz-utils
	apt-utils
	e2fsprogs
	parted
	gawk
	bc
)

[ "$(id -u)" -eq 0 ] || exec sudo -E env KOLA_BUILDROOT="${ROOT}" "$0" "$@"

valid_root() {
	[ -x "${ROOT}/bin/bash" ] && [ -f "${ROOT}/etc/debian_version" ]
}

missing_pkgs() {
	local p
	for p in "${CHROOT_PKGS[@]}"; do
		chroot "${ROOT}" dpkg-query -W -f='${Status}' "$p" 2>/dev/null |
			grep -q "install ok installed" || echo "$p"
	done
}

repair_root() {
	echo ">> repairing ${ROOT}: mounting pseudo-filesystems"
	mkdir -p "${ROOT}/dev" "${ROOT}/dev/pts" "${ROOT}/proc" "${ROOT}/sys"
	mountpoint -q "${ROOT}/dev" || mount --bind /dev "${ROOT}/dev"
	mountpoint -q "${ROOT}/dev/pts" || mount --bind /dev/pts "${ROOT}/dev/pts"
	mountpoint -q "${ROOT}/proc" || mount -t proc proc "${ROOT}/proc"
	mountpoint -q "${ROOT}/sys" || mount --bind /sys "${ROOT}/sys"
	cp -f /etc/resolv.conf "${ROOT}/etc/resolv.conf"

	local rc=0
	chroot "${ROOT}" apt-get update || rc=$?
	if [ "${rc}" -eq 0 ]; then
		# shellcheck disable=SC2086
		chroot "${ROOT}" apt-get install -y --no-install-recommends "${CHROOT_PKGS[@]}" || rc=$?
	fi

	for m in "${ROOT}/dev/pts" "${ROOT}/dev" "${ROOT}/proc" "${ROOT}/sys"; do
		mountpoint -q "$m" 2>/dev/null && umount "$m" || true
	done
	return "${rc}"
}

echo ">> host packages"
apt-get update
apt-get install -y --no-install-recommends "${HOST_PKGS[@]}"

[ -f "${DEBIAN_KEYRING}" ] || {
	echo "ERROR: ${DEBIAN_KEYRING} missing - Debian archive keys unavailable, apt cannot verify bookworm" >&2
	exit 1
}

if [ -n "${SUDO_USER:-}" ] && ! id -nG "${SUDO_USER}" | tr ' ' '\n' | grep -qx kvm; then
	usermod -aG kvm "${SUDO_USER}"
	echo ">> ${SUDO_USER} added to group kvm (log out/in before QEMU KVM acceleration works)"
fi

if [ -d "${ROOT}" ] && ! valid_root; then
	STAMP=$(date +%Y%m%d-%H%M%S)
	echo ">> incomplete build root detected (no /bin/bash, no /etc/debian_version)"
	echo ">> moving it aside: ${ROOT}.incomplete-${STAMP}"
	mv "${ROOT}" "${ROOT}.incomplete-${STAMP}"
fi

if valid_root; then
	echo ">> reusing existing build root: ${ROOT}"
	MISSING=$(missing_pkgs || true)
	if [ -n "${MISSING}" ]; then
		echo ">> missing packages:"
		echo "${MISSING}" | sed 's/^/     /'
		repair_root
	fi
else
	echo ">> creating build root: ${ROOT}"
	mkdir -p "$(dirname "${ROOT}")"
	mmdebstrap \
		--variant=apt \
		--keyring="${DEBIAN_KEYRING}" \
		--include="$(IFS=,; echo "${CHROOT_PKGS[*]}")" \
		"${SUITE}" "${ROOT}" "${MIRROR}"
fi

echo ">> verifying chroot packages"
MISSING=$(missing_pkgs || true)
if [ -n "${MISSING}" ]; then
	echo "ERROR: build root still incomplete:" >&2
	echo "${MISSING}" | sed 's/^/   MISSING: /' >&2
	exit 1
fi

echo ">> build root ready: ${ROOT}"
du -sh "${ROOT}" 2>/dev/null || true
