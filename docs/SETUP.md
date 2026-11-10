# Setup

Everything needed to build Kola OS from a fresh clone.

## 1. Requirements

| Item | Minimum | Notes |
|---|---|---|
| Host OS | Debian 12, Ubuntu 24.04, Pop!_OS 24.04 | anything apt-based; `live-build` runs in a Debian chroot, not on the host |
| Architecture | amd64 | the image is `amd64` |
| Disk | 25 GB free on `/` | build aborts below 20 GB |
| RAM | 4 GB host | build is disk/network bound |
| Network | ~1 GB download | mirror is auto-benchmarked |
| Access | passwordless or interactive `sudo` | root is required to chroot |
| KVM | `/dev/kvm` | only for QEMU testing; `sudo usermod -aG kvm $USER` + re-login |

Package lists are data files, not hardcoded in scripts:

- `env/host-packages.txt` — installed on the host via apt
- `env/chroot-packages.txt` — installed inside the Debian 12 build root

## 2. Clone and provision

```bash
git clone https://github.com/<owner>/kola-os.git
cd kola-os
./env/bootstrap.sh
```

`bootstrap.sh` performs, idempotently:

1. Installs the host packages from `env/host-packages.txt` (system-wide).
2. Adds you to the `kvm` group if needed.
3. Creates the shared Debian 12 root at `~/.cache/debian12-live-build`
   (`mmdebstrap`, ~700 MB, 5–15 min) — or reuses it if it already exists.
4. Installs `env/chroot-packages.txt` inside that root.
5. Verifies every package with `dpkg-query`; exits non-zero on anything missing.

Re-running is safe: a valid root is repaired in place, a partial one is moved
aside to `~/.cache/debian12-live-build.incomplete-<timestamp>` and rebuilt.

### The root is shared

One Debian 12 root serves every project on the machine. A second project only
needs `KOLA_BUILDROOT` pointed at it (the default already does):

```bash
KOLA_BUILDROOT=~/.cache/debian12-live-build ./env/bootstrap.sh
```

## 3. Verify before building

```bash
make verify
```

Checks, in order: host packages, OVMF firmware, `/dev/kvm`, ≥20 GB free, mirror
throughput, Debian root + 20 chroot packages, `auto/config` option values, shell
syntax, hook permissions, `auto/clean` recursion. Any failure aborts the build.

## 4. Build

```bash
make build
```

| Stage | Typical time | What happens |
|---|---|---|
| `lb config` | 5 s | applies `auto/config` |
| `lb bootstrap` | 2–5 min | debootstrap bookworm |
| `lb chroot` | 10–20 min | installs the package set, runs hooks, patches initramfs |
| `lb binary` | 3–5 min | squashfs, GRUB EFI image, xorriso |
| checksum | instant | `kola-os-*.iso.sha256` |

Output: `kola-os-*.iso` in the repo root.

Only one build may run at a time: `build.sh` takes `.lock` with `flock` and a
second invocation exits with `another Kola OS build is already running`. The
mirror is re-benchmarked when `.mirror` is older than 1 h, so a slow build is
usually a degraded mirror rather than a bad config — see
`./env/mirror.sh --show`.

## 5. Test

```bash
make test                       # 1024 MB: non-toram path
MEM=2048 make test              # 2048 MB: auto-toram path
```

Both boot under OVMF/UEFI. KVM is used when accessible, TCG otherwise.

## 6. Write a USB stick

See `docs/USB.md` (Rufus on Windows, `dd` on Linux, Secure Boot must be off).

## Maintenance

```bash
./env/mirror.sh --force    # re-benchmark mirrors now (1 h cache otherwise)
make reset                 # unmount, lb clean, remove artefacts, archive logs
make clean                 # drop the ISO and build logs
```

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `NO_PUBKEY …` during bootstrap | Debian archive keys absent on host | `./env/bootstrap.sh` installs `debian-archive-keyring` |
| `mount: not found` in `lb chroot` | root created without runtime tools | `./env/bootstrap.sh` (repair mode) |
| `cp: error reading 'chroot/proc/1/task/1/mem'` | live procfs leaked into the bootstrap cache | `--cache-stages none` is set; run `make reset` |
| `auto/clean: … lb clean` fork loop | `auto/clean` calling `lb` | fixed; gate rejects it |
| Gate: mirror < 100 KB/s | link or mirror degraded | `./env/mirror.sh --force`, or `KOLA_MIN_KBPS=50 make build` |
| `umount: target is busy` | leftover chroot mount | `make reset` |
| `another Kola OS build is already running` | `.lock` held by a live build | wait, or `make reset` if it is dead |
| ISO boots to `grub>` | GRUB path mismatch | see `docs/BUILD.md` risk list |
| No Wi-Fi networks | firmware or `wpasupplicant` | see `docs/DECISIONS.md` |

## Proxy

`lb` runs inside the chroot; export these before `make build` so they are
propagated by `env/enter.sh`:

```bash
export http_proxy=http://proxy:8080
export https_proxy=$http_proxy
export no_proxy=localhost,127.0.0.1
```
