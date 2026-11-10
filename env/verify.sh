#!/usr/bin/env bash
# Pre-build gate. Nothing is built unless every check passes.
# Checks: host packages, OVMF, KVM, disk, mirror, chroot, config, repo syntax.
set -uo pipefail

ROOT="${KOLA_BUILDROOT:-$HOME/.cache/debian12-live-build}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0

ok()   { printf '  [ OK ]   %s\n' "$1"; }
bad()  { printf '  [ FAIL ] %s\n' "$1"; fail=1; }
warn() { printf '  [ WARN ] %s\n' "$1"; }
skip() { printf '  [ -- ]   %s\n' "$1"; }

read_list() { grep -vE '^[[:space:]]*(#|$)' "$1" | awk '{print $1}'; }

echo "== host packages"
if [ -f "${REPO}/env/host-packages.txt" ]; then
	while read -r p; do
		if dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q "install ok installed"; then
			ok "$p"
		else
			bad "$p (run ./env/bootstrap.sh)"
		fi
	done < <(read_list "${REPO}/env/host-packages.txt")
else
	bad "env/host-packages.txt missing"
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
	skip "/dev/kvm not writable - 'sudo usermod -aG kvm \$USER' then re-login"
else
	skip "/dev/kvm absent - QEMU will run under TCG only"
fi

echo "== disk space"
AVAIL=$(df -Pk "$REPO" | awk 'NR==2{print $4}')
MIN_KB=$((20 * 1024 * 1024))
if [ "${AVAIL:-0}" -ge "${MIN_KB}" ]; then
	ok "$((AVAIL/1024/1024)) GB free (min 20 GB)"
else
	bad "need 20 GB free, have $((AVAIL/1024/1024)) GB"
fi

echo "== mirror throughput"
MIRROR_LINE=$("$REPO/env/mirror.sh" --select 2>/dev/null || true)
MIRROR=$(echo "${MIRROR_LINE}" | awk '{print $1}')
KBS=$(echo "${MIRROR_LINE}" | awk '{print $2}')
MIN_KBPS="${KOLA_MIN_KBPS:-100}"
if [ -z "${MIRROR}" ]; then
	bad "no reachable Debian mirror (see env/mirrors.txt)"
elif [ "${KBS:-0}" -ge 250 ]; then
	ok "mirror ${MIRROR} (${KBS} KB/s)"
elif [ "${KBS:-0}" -ge "${MIN_KBPS}" ]; then
	warn "mirror ${MIRROR} (${KBS} KB/s) - slower than ideal, build will take longer"
else
	bad "best mirror ${MIRROR} only ${KBS:-0} KB/s (min ${MIN_KBPS}); every mirror is slow right now"
	skip "retry later: ./env/mirror.sh --force   (or accept with KOLA_MIN_KBPS=50)"
fi

pkg_installed() {
	local p="$1"
	if [ "$(id -u)" -eq 0 ]; then
		chroot "${ROOT}" dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q "install ok installed"
	else
		awk -v pkg="$p" 'BEGIN{RS="";FS="\n"} $1=="Package: "pkg && /Status: install ok installed/ {f=1} END{exit !f}' \
			"${ROOT}/var/lib/dpkg/status" 2>/dev/null
	fi
}

echo "== build root: ${ROOT}"
if [ -x "${ROOT}/bin/bash" ] && [ -f "${ROOT}/etc/debian_version" ]; then
	ok "Debian $(cat "${ROOT}/etc/debian_version" 2>/dev/null || echo '?') root present"
	while read -r p; do
		if pkg_installed "$p"; then
			ok "chroot: $p"
		else
			bad "chroot: $p missing (run ./env/bootstrap.sh)"
		fi
	done < <(read_list "${REPO}/env/chroot-packages.txt")
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

# Requiring both mirror families guards the exact bug that sent a 3 h build at
# the Debian CDN while .mirror said ftp.nl: LB_MIRROR_* is only what gets baked
# into the image, bootstrap_debootstrap reads LB_PARENT_MIRROR_*.
MIRRORSEL=$(awk '{print $1}' "$REPO/.mirror" 2>/dev/null || true)
if grep -q -- '--parent-mirror-bootstrap' "$REPO/auto/config" 2>/dev/null; then
	ok "config: parent mirrors follow .mirror (${MIRRORSEL:-unset})"
else
	bad "config: --parent-mirror-bootstrap missing (build would use deb.debian.org)"
fi
if grep -q 'flock -n 9' "$REPO/build.sh" 2>/dev/null; then
	ok "build.sh: single-instance lock"
else
	bad "build.sh: no flock guard (concurrent builds corrupt the tree)"
fi
if [ -f "$REPO/config/bootstrap" ] && [ -n "${MIRRORSEL}" ]; then
	STALE=$(sed -n 's/^LB_PARENT_MIRROR_BOOTSTRAP="\(.*\)"$/\1/p' "$REPO/config/bootstrap")
	if [ -n "${STALE}" ] && [ "${STALE%/}" != "${MIRRORSEL%/}" ]; then
		warn "generated config/bootstrap still points at ${STALE} - 'lb config' will rewrite it"
	else
		ok "generated config/bootstrap matches .mirror"
	fi
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
