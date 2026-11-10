#!/usr/bin/env bash
# Choose the fastest Debian mirror for this network and cache the decision.
#
#   ./env/mirror.sh --select   benchmark all candidates (cached for 1 h)
#   ./env/mirror.sh --force    re-benchmark now
#   ./env/mirror.sh --show     print "URL KBPS" currently selected
#
# Writes .mirror in the repo root: "<url> <kbps>". auto/config reads it, so
# every lb config run uses the measured mirror instead of a hardcoded guess.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIST="${KOLA_MIRRORS:-${REPO}/env/mirrors.txt}"
CACHE="${REPO}/.mirror"
SECONDS_PER_TEST="${KOLA_MIRROR_SECONDS:-6}"
PASSES="${KOLA_MIRROR_PASSES:-1}"
TTL="${KOLA_MIRROR_TTL:-3600}"

bench() {
	local url="$1" best=0 pass raw
	for pass in $(seq 1 "${PASSES}"); do
		raw=$(curl --max-time "${SECONDS_PER_TEST}" -s -r 0-4000000 -o /dev/null \
			-w '%{speed_download}' \
			"${url}/dists/bookworm/main/binary-amd64/Packages.gz" 2>/dev/null || true)
		raw="${raw%%.*}"
		raw="${raw:-0}"
		[ "${raw}" -gt "${best}" ] && best="${raw}"
	done
	echo $((best / 1024))
}

case "${1:---select}" in
--show)
	cat "${CACHE}" 2>/dev/null || echo "unset 0"
	exit 0
	;;
--select | --force)
	if [ "${1}" = "--select" ] && [ -f "${CACHE}" ] &&
		[ $(( $(date +%s) - $(stat -c %Y "${CACHE}") )) -lt "${TTL}" ]; then
		cat "${CACHE}"
		exit 0
	fi
	;;
*)
	echo "usage: $0 [--select|--force|--show]" >&2
	exit 2
	;;
esac

best_url=""
best_kbps=0

while read -r url _; do
	[ -z "${url}" ] && continue
	case "${url}" in \#*) continue ;; esac
	kbps=$(bench "${url}")
	printf '   %-42s %5s KB/s\n' "${url}" "${kbps}" >&2
	if [ "${kbps}" -gt "${best_kbps}" ]; then
		best_kbps="${kbps}"
		best_url="${url}"
	fi
done <"${LIST}"

[ -n "${best_url}" ] || { echo "ERROR: no reachable mirror in ${LIST}" >&2; exit 1; }

printf '%s %s\n' "${best_url}" "${best_kbps}" >"${CACHE}"
cat "${CACHE}"
