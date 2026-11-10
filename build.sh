#!/bin/bash
# Kola OS build driver.
# MUST run as root inside the Debian 12 chroot created by env/bootstrap.sh.
set -euo pipefail
cd "$(dirname "$0")"

if [ "$(id -u)" -ne 0 ]; then
	echo "ERROR: run ./env/enter.sh (builds inside the Debian chroot)" >&2
	exit 1
fi

if ! command -v lb >/dev/null; then
	echo "ERROR: live-build missing. Run: apt-get install -y --no-install-recommends live-build" >&2
	exit 1
fi

export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C

apt-get update -qq
apt-get install -y --no-install-recommends live-build ca-certificates

echo ">> cleaning previous state"
lb clean --purge || true
rm -rf binary cache .tmp

echo ">> configuring"
lb config

echo ">> building"
LOG="build-$(date +%Y%m%d-%H%M).log"
lb build 2>&1 | tee "${LOG}"

ISO=$(ls -1 kola-os-*.iso 2>/dev/null | head -1 || true)
if [ -z "${ISO}" ]; then
	echo "ERROR: no ISO produced, see ${LOG}" >&2
	exit 1
fi

echo ">> verifying live kernel paths (used by the GRUB override)"
if command -v isoinfo >/dev/null; then
	isoinfo -f -R -i "${ISO}" | grep -E '^/live/(vmlinuz|initrd\.img)$' || {
		echo "WARNING: /live/vmlinuz or /live/initrd.img not found - check config/bootloaders/grub-efi/grub.cfg" >&2
	}
fi

sha256sum "${ISO}" > "${ISO}.sha256"
ls -lh "${ISO}"
echo ">> done"
