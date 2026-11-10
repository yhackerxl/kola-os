#!/usr/bin/env bash
# Pre-build gate. Nothing is built unless every check passes.
# Checks: host tools, OVMF, KVM, disk space, chroot toolchain, repo syntax.
set -uo pipefail

ROOT="${KOLA_BUILDROOT:-$HOME/.cache/debian12-live-build}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0

ok()   { printf '  [ OK ]   %s\n' "$1"; }
bad()  { printf '  [ FAIL ] %s\n' "$1"; fail=1; }
warn() { printf '  [ WARN ] %s\n' "$1"; }
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
if [ -f /usr/share/keyrings/debian-archive-keyring.gpg ]; then
	ok "debian-archive-keyring"
else
	bad "debian-archive-keyring (run ./env/bootstrap.sh)"
fi

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

pkg_installed() {
	local p="$1"
	if [ "$(id -u)" -eq 0 ]; then
		chroot "${ROOT}" dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q "install ok installed"
	else
		# non-root: read the status database directly (world-readable)
		awk -v pkg="$p" 'BEGIN{RS="";FS="\n"} $1=="Package: "pkg && /Status: install ok installed/ {f=1} END{exit !f}' \
			"${ROOT}/var/lib/dpkg/status" 2>/dev/null
	fi
}

echo "== build root: ${ROOT}"
if [ -x "${ROOT}/bin/bash" ] && [ -f "${ROOT}/etc/debian_version" ]; then
	ok "Debian $(cat "${ROOT}/etc/debian_version" 2>/dev/null || echo '?') root present"
	for p in live-build debootstrap squashfs-tools xorriso mtools dosfstools \
		grub-efi-amd64-bin grub-pc-bin syslinux-common isolinux; do
		if pkg_installed "$p"; then
			ok "chroot: $p"
		else
			bad "chroot: $p missing"
		fi
	done
else
	bad "build root missing or incomplete (no /bin/bash) - run ./env/bootstrap.sh"
fi

echo "== live-build option values"
check_opt() {
	local opt="$1"; shift
	local val
	val=$(grep -o -- "--${opt} [^ \\\\]*" "$REPO/auto/config" 2>/dev/null | head -1 | awk '{print $2}')
	[ -n "${val}" ] || return 0
	local allowed
	for allowed in "$@"; do
		if [ "${val}" = "${allowed}" ]; then
			ok "config: --${opt}=${val}"
			return 0
		fi
	done
	bad "config: --${opt}=${val} (allowed: $*)"
}
check_opt initramfs-compression bzip2 gzip lzma
check_opt compression bzip2 gzip lzip xz none
check_opt debian-installer cdrom netinst netboot businesscard live none
check_opt memtest memtest86+ memtest86 none
check_opt uefi-secure-boot auto enable disable
check_opt firmware-chroot true false
check_opt firmware-binary true false
check_opt bootloader grub-efi grub-pc syslinux
check_opt architectures amd64
check_opt binary-images iso-hybrid iso hdd netboot

# debootstrap leaves a live /proc inside chroot/; live-build's bootstrap cache
# then copies procfs and dies on /proc/1/task/1/mem. Skipping that stage is the
# only reliable fix (LB_CACHE=false still forces bootstrap caching).
if grep -q -- '--cache-stages none' "$REPO/auto/config" 2>/dev/null; then
	ok "config: --cache-stages=none (bootstrap cache disabled)"
else
	bad "config: --cache-stages none missing (proc leak in bootstrap cache)"
fi

echo "== mirror throughput"
MIRROR=$(grep -o -- '--mirror-chroot [^ \\]*' "$REPO/auto/config" 2>/dev/null | head -1 | awk '{print $2}')
if [ -n "${MIRROR}" ]; then
	r=$(curl --max-time 6 -s -r 0-2000000 -o /dev/null -w '%{speed_download}' \
		"${MIRROR}/dists/bookworm/main/binary-amd64/Packages.gz" 2>/dev/null)
	KBS=$(awk -v v="${r:-0}" 'BEGIN{printf "%.0f", v/1024}')
	if [ "${KBS}" -ge 250 ]; then
		ok "mirror ${MIRROR} (${KBS} KB/s)"
	elif [ "${KBS}" -ge 100 ]; then
		warn "mirror ${MIRROR} slow (${KBS} KB/s) - build will take longer"
	elif [ "${KBS}" -gt 0 ]; then
		bad "mirror ${MIRROR} crawling (${KBS} KB/s) - change --mirror-* in auto/config"
	else
		bad "mirror ${MIRROR} unreachable"
	fi
else
	skip "no --mirror-chroot set, using live-build default"
fi

echo "== repository"
if (cd "$REPO" && bash -n build.sh env/*.sh test/*.sh) 2>/dev/null; then ok "shell syntax"; else bad "shell syntax"; fi
for f in "$REPO"/config/hooks/normal/*.hook.chroot; do
	[ -e "$f" ] || continue
	# live-build's own defaults are symlinks into /usr/share/live/build
	[ -L "$f" ] && continue
	[ -x "$f" ] || bad "not executable: $(basename "$f")"
	sh -n "$f" || bad "syntax: $(basename "$f")"
done
[ -f "$REPO/auto/config" ] && ok "auto/config" || bad "auto/config missing"
[ -f "$REPO/config/bootloaders/grub-efi/grub.cfg" ] && ok "GRUB override" || bad "GRUB override missing"

# recursion guard: auto/clean is called by `lb clean` and must not call lb
if grep -vE '^[[:space:]]*#' "$REPO/auto/clean" 2>/dev/null | grep -qE '(^|[[:space:];&|])lb[[:space:]]+clean'; then
	bad "auto/clean calls 'lb clean' (fork loop)"
else
	ok "auto/clean has no lb recursion"
fi

echo
if [ "${fail}" -eq 0 ]; then
	echo "VERIFY: PASS - safe to run make build"
	exit 0
fi
echo "VERIFY: FAIL - fix the items above"
exit 1
