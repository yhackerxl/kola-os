#!/usr/bin/env bash
# Boot the built ISO in QEMU with UEFI firmware.
# Default 1024 MB exercises the non-toram path; use MEM=2048 for the toram path.
set -euo pipefail

ISO="${1:-}"
MEM="${MEM:-1024}"
CPUS="${CPUS:-2}"

[ -n "${ISO}" ] || { echo "usage: $0 kola-os-*.iso" >&2; exit 1; }
[ -f "${ISO}" ] || { echo "ERROR: ${ISO} not found" >&2; exit 1; }

CODE=/usr/share/OVMF/OVMF_CODE.fd
VARS_SRC=/usr/share/OVMF/OVMF_VARS.fd
[ -f "${CODE}" ] || { echo "ERROR: install ovmf" >&2; exit 1; }

VARS=$(mktemp /tmp/opencode/kola-vars-XXXX.fd)
cp "${VARS_SRC}" "${VARS}"
trap 'rm -f "${VARS}"' EXIT

exec qemu-system-x86_64 \
	-enable-kvm -cpu host -smp "${CPUS}" -m "${MEM}" \
	-drive "if=pflash,format=raw,readonly=on,file=${CODE}" \
	-drive "if=pflash,format=raw,file=${VARS}" \
	-cdrom "${ISO}" \
	-boot order=d \
	-vga std -display gtk
