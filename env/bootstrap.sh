#!/usr/bin/env bash
# Provision the shared Debian 12 live-build root.
#
# GLOBAL / REUSABLE: the root lives outside this repo and is shared by every
# project. A new clone only needs to run this script once per machine.
#
# Self-healing:
#   - incomplete root (no /bin/bash) -> moved aside, recreated
#   - valid root, missing packages   -> repaired with apt inside the chroot
#
# Package lists are data files (single source of truth):
#   env/host-packages.txt    installed on the host
#   env/chroot-packages.txt  installed inside the Debian root
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="${KOLA_BUILDROOT:-$HOME/.cache/debian12-live-build}"
SUITE="${KOLA_SUITE:-bookworm}"
MIRROR="${KOLA_MIRROR:-http://deb.debian.org/debian}"
DEBIAN_KEYRING=/usr/share/keyrings/debian-archive-keyring.gpg

read_list() {
	grep -vE '^[[:space:]]*(#|$)' "$1" | awk '{print $1}'
}

HOST_FILE="${REPO}/env/host-packages.txt"
CHROOT_FILE="${REPO}/env/chroot-packages.txt"

[ -f "${HOST_FILE}" ] || { echo "ERROR: ${HOST_FILE} missing" >&2; exit 1; }
[ -f "${CHROOT_FILE}" ] || { echo "ERROR: ${CHROOT_FILE} missing" >&2; exit 1; }

mapfile -t HOST_PKGS < <(read_list "${HOST_FILE}")
mapfile -t CHROOT_PKGS < <(read_list "${CHROOT_FILE}")

[ "$(id -u)" -eq 0 ] || exec sudo -E env KOLA_BUILDROOT="${ROOT}" "$0" "$@"

valid_root() {
	[ -x "${ROOT}/bin/bash" ] && [ -f "${ROOT}/etc/debian_version" ]
}

missing_pkgs() {
	local p
	for p in "$@"; do
		chroot "${ROOT}" dpkg-query -W -f='${Status}' "$p" 2>/dev/null |
			grep -q "install ok installed" || echo "$p"
	done
}

mount_pseudo() {
	mkdir -p "${ROOT}/dev" "${ROOT}/dev/pts" "${ROOT}/proc" "${ROOT}/sys"
	mountpoint -q "${ROOT}/dev" || mount --bind /dev "${ROOT}/dev"
	mountpoint -q "${ROOT}/dev/pts" || mount --bind /dev/pts "${ROOT}/dev/pts"
	mountpoint -q "${ROOT}/proc" || mount -t proc proc "${ROOT}/proc"
	mountpoint -q "${ROOT}/sys" || mount --bind /sys "${ROOT}/sys"
	cp -f /etc/resolv.conf "${ROOT}/etc/resolv.conf"
}

unmount_pseudo() {
	local m
	for m in "${ROOT}/dev/pts" "${ROOT}/dev" "${ROOT}/proc" "${ROOT}/sys"; do
		if mountpoint -q "$m" 2>/dev/null; then
			umount "$m" 2>/dev/null || umount -l "$m" 2>/dev/null || true
		fi
	done
}

repair_root() {
	echo ">> repairing ${ROOT}: installing ${#CHROOT_PKGS[@]} package(s)"
	mount_pseudo
	trap unmount_pseudo EXIT

	local rc=0
	chroot "${ROOT}" apt-get update || rc=$?
	if [ "${rc}" -eq 0 ]; then
		chroot "${ROOT}" apt-get install -y --no-install-recommends "${CHROOT_PKGS[@]}" || rc=$?
	fi

	unmount_pseudo
	trap - EXIT
	return "${rc}"
}

echo ">> host packages (${HOST_FILE##*/})"
apt-get update
apt-get install -y --no-install-recommends "${HOST_PKGS[@]}"

[ -f "${DEBIAN_KEYRING}" ] || {
	echo "ERROR: ${DEBIAN_KEYRING} missing - Debian archive keys unavailable, apt cannot verify ${SUITE}" >&2
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
	MISSING=$(missing_pkgs "${CHROOT_PKGS[@]}" || true)
	if [ -n "${MISSING}" ]; then
		echo ">> missing chroot packages:"
		echo "${MISSING}" | sed 's/^/     /'
		repair_root
	fi
else
	echo ">> creating build root: ${ROOT} (${#CHROOT_PKGS[@]} packages)"
	mkdir -p "$(dirname "${ROOT}")"
	mmdebstrap \
		--variant=apt \
		--keyring="${DEBIAN_KEYRING}" \
		--include="$(IFS=,; echo "${CHROOT_PKGS[*]}")" \
		"${SUITE}" "${ROOT}" "${MIRROR}"
fi

echo ">> verifying chroot packages"
MISSING=$(missing_pkgs "${CHROOT_PKGS[@]}" || true)
if [ -n "${MISSING}" ]; then
	echo "ERROR: build root still incomplete:" >&2
	echo "${MISSING}" | sed 's/^/   MISSING: /' >&2
	exit 1
fi

echo ">> build root ready: ${ROOT}"
du -sh "${ROOT}" 2>/dev/null || true
