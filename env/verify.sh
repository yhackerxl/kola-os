#!/usr/bin/env bash
# Pre-build gate. Nothing is built unless every check passes.
# Checks: host tools, OVMF, KVM, disk space, chroot toolchain, repo syntax.
set -uo pipefail

ROOT="${KOLA_BUILDROOT:-$HOME/.cache/debian12-live-build}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0

ok()   { printf '  [ OK ]   %s\n' "$1"; }
bad()  { printf '  [ FAIL ] %s\n' "$1"; fail=1; }
skip() { printf '  [ -- ]   %s\n' "$1"; }

echo "== host tools"
if command -v mmdebstrap >/dev/null || command -v debootstrap >/dev/null; then
	ok "bootstrap tool"
else
	bad "mmdebstrap/debootstrap (run ./env/bootstrap.sh)"
fi
for c in qemu-system-x86_64; do
	if command -v "$c" >/dev/null; then ok "$c"; else bad "$c (run ./env/bootstrap.sh)"; fi
done

echo "== UEFI firmware"
OVMF_CODE=""
for f in /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd \
	/usr/share/ovmf/OVMF.fd /usr/share/OVMF/OVMF_CODE_4M.ms.fd; do
	[ -f "$f" ] && { OVMF_CODE="$f"; break; }
done
if [ -n "${OVMF_CODE}" ]; then ok "OVMF: ${OVMF_CODE}"; else bad "OVMF firmware not found (install ovmf)"; fi

echo "== virtualization"
if [ -w /dev/kvm ]; then
	ok "/dev/kvm accessible"
elif [ -e /dev/kvm ]; then
	skip "/dev/kvm exists but not writable - QEMU will fall back to TCG (slow) or re-login after usermod -aG kvm"
else
	skip "/dev/kvm absent - QEMU will run under TCG only"
fi

echo "== disk space"
AVAIL=$(df -Pk "$REPO" | awk 'NR==2{print $4}')
if [ "${AVAIL:-0}" -gt 20000000 ]; then ok "$((AVAIL/1024/1024)) GB free"; else bad "need ~20 GB free, have $((AVAIL/1024/1024)) GB"; fi

echo "== build root: ${ROOT}"
if [ -d "${ROOT}/etc" ]; then
	ok "root exists"
	for p in live-build debootstrap squashfs-tools xorriso mtools dosfstools \
		grub-efi-amd64-bin grub-pc-bin syslinux-common isolinux; do
		if chroot "${ROOT}" dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q "install ok installed"; then
			ok "chroot: $p"
		else
			bad "chroot: $p missing"
		fi
	done
else
	bad "build root missing - run ./env/bootstrap.sh"
fi

echo "== repository"
if (cd "$REPO" && bash -n build.sh env/*.sh test/*.sh) 2>/dev/null; then ok "shell syntax"; else bad "shell syntax"; fi
for f in "$REPO"/config/hooks/normal/*.hook.chroot; do
	[ -x "$f" ] || bad "not executable: $(basename "$f")"
	sh -n "$f" || bad "syntax: $(basename "$f")"
done
[ -f "$REPO/auto/config" ] && ok "auto/config" || bad "auto/config missing"
[ -f "$REPO/config/bootloaders/grub-efi/grub.cfg" ] && ok "GRUB override" || bad "GRUB override missing"

echo
if [ "${fail}" -eq 0 ]; then
	echo "VERIFY: PASS - safe to run make build"
	exit 0
fi
echo "VERIFY: FAIL - fix the items above"
exit 1
