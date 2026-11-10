#!/usr/bin/env bash
# Boot the built ISO in QEMU with UEFI firmware.
#   MEM=1024 tests the non-toram path (default)
#   MEM=2048 tests the auto-toram path
set -euo pipefail

ISO="${1:-}"
MEM="${MEM:-1024}"
CPUS="${CPUS:-2}"

[ -n "${ISO}" ] || { echo "usage: $0 kola-os-*.iso" >&2; exit 1; }
[ -f "${ISO}" ] || { echo "ERROR: ${ISO} not found" >&2; exit 1; }

CODE_SRC=""
for f in /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd /usr/share/ovmf/OVMF.fd; do
	[ -f "$f" ] && { CODE_SRC="$f"; break; }
done
[ -n "${CODE_SRC}" ] || { echo "ERROR: OVMF_CODE not found (install ovmf)" >&2; exit 1; }

VARS_SRC=""
for f in /usr/share/OVMF/OVMF_VARS_4M.fd /usr/share/OVMF/OVMF_VARS.fd /usr/share/OVMF/OVMF_VARS_4M.ms.fd; do
	[ -f "$f" ] && { VARS_SRC="$f"; break; }
done
[ -n "${VARS_SRC}" ] || { echo "ERROR: OVMF_VARS not found (install ovmf)" >&2; exit 1; }

mkdir -p /tmp/opencode
VARS=$(mktemp /tmp/opencode/kola-vars-XXXXXX.fd)
cp "${VARS_SRC}" "${VARS}"
trap 'rm -f "${VARS}"' EXIT

ACCEL=()
if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
	ACCEL=(-enable-kvm -cpu host)
	echo ">> KVM acceleration"
else
	ACCEL=(-accel tcg)
	echo ">> no KVM access: TCG (slow). Re-login after 'sudo usermod -aG kvm \$USER'."
fi

exec qemu-system-x86_64 \
	"${ACCEL[@]}" -smp "${CPUS}" -m "${MEM}" \
	-drive "if=pflash,format=raw,readonly=on,file=${CODE_SRC}" \
	-drive "if=pflash,format=raw,file=${VARS}" \
	-cdrom "${ISO}" \
	-boot order=d \
	-vga std -display gtk
