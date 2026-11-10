#!/usr/bin/env bash
# Enter the shared Debian 12 build root and run the build.
# Only this repo is bind-mounted at /build; the host filesystem is untouched.
set -euo pipefail

ROOT="${KOLA_BUILDROOT:-$HOME/.cache/debian12-live-build}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

[ "$(id -u)" -eq 0 ] || exec sudo -E "$0" "$@"

[ -d "${ROOT}/etc" ] || {
	echo "ERROR: ${ROOT} missing. Run ./env/bootstrap.sh first." >&2
	exit 1
}

cleanup() {
	for m in "${ROOT}/build" "${ROOT}/dev/pts" "${ROOT}/dev" "${ROOT}/proc" "${ROOT}/sys"; do
		mountpoint -q "$m" 2>/dev/null && umount "$m" || true
	done
}
trap cleanup EXIT
cleanup

mkdir -p "${ROOT}/build" "${ROOT}/dev/pts" "${ROOT}/proc" "${ROOT}/sys"

mount --bind "${REPO}" "${ROOT}/build"
mount --bind /dev "${ROOT}/dev"
mount --bind /dev/pts "${ROOT}/dev/pts"
mount -t proc proc "${ROOT}/proc"
mount --bind /sys "${ROOT}/sys"
cp -f /etc/resolv.conf "${ROOT}/etc/resolv.conf"

chroot "${ROOT}" /bin/bash -lc 'cd /build && ./build.sh'
