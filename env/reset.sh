#!/usr/bin/env bash
# Failure recovery. Safe to run at any time; idempotent.
#   1. unmount stale chroot pseudo-filesystems
#   2. lb clean --purge inside the Debian 12 chroot
#   3. remove chroot/cache/.build
#   4. archive logs to logs/ (never delete them)
set -euo pipefail

ROOT="${KOLA_BUILDROOT:-$HOME/.cache/debian12-live-build}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

[ "$(id -u)" -eq 0 ] || exec sudo -E env KOLA_BUILDROOT="${ROOT}" "$0" "$@"

cd "${REPO}"

echo ">> unmounting stale pseudo-filesystems"
for d in chroot/proc chroot/sys chroot/dev/pts chroot/dev; do
	if mountpoint -q "${REPO}/${d}" 2>/dev/null; then
		umount -l "${REPO}/${d}" 2>/dev/null || true
		echo "   unmounted ${d}"
	fi
done

if [ -d "${ROOT}/etc" ]; then
	echo ">> lb clean --purge (inside chroot)"
	"${REPO}/env/enter.sh" lb clean --purge || true
else
	echo ">> chroot missing, skipping lb clean"
fi

echo ">> removing build artefacts"
rm -rf "${REPO}/chroot" "${REPO}/cache" "${REPO}/.build"

if ls "${REPO}"/*.log >/dev/null 2>&1; then
	mkdir -p "${REPO}/logs"
	mv "${REPO}"/*.log "${REPO}/logs"/
	echo ">> logs moved to logs/"
fi

echo ">> reset complete"
