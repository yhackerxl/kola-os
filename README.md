# Kola OS

Ultra-lightweight Debian 12 live distribution for secondary schools in Tanzania.
Boots from a USB stick, needs no hard drive, and runs entirely in RAM when the
machine has enough memory.

- **Base** Debian 12 (Bookworm), `amd64`, UEFI
- **Session** LightDM autologin → Openbox
- **Apps** LXTerminal, PCManFM, Geany, Epiphany, LXTask — nothing else
- **Policy** zero bloat (`--apt-recommends false`), no printing, no persistence
- **RAM** `toram` automatically at ≥1600 MB, otherwise runs from the stick

## Quick start

```bash
git clone https://github.com/yhackerxl/kola-os.git
cd kola-os
./env/bootstrap.sh     # one-time per machine: host tools + shared Debian 12 root
make verify            # hard gate, must PASS
make build             # produces kola-os-*.iso
make test              # boot it in QEMU/UEFI
```

Full instructions, requirements and troubleshooting: **`docs/SETUP.md`**.

## How the build is isolated

`live-build` must run as root on Debian 12. This repo never uses the host as the
build root:

```
env/bootstrap.sh  ->  ~/.cache/debian12-live-build   (shared, reusable)
env/enter.sh      ->  bind-mounts this repo at /build, chroots, runs build.sh
build.sh          ->  lb clean -> lb config -> lb build -> ISO + sha256
```

The Debian root is shared by every project on the machine; a new clone reuses it.
Package requirements are data files, not hardcoded lists:

| File | Installed where |
|---|---|
| `env/host-packages.txt` | host, via apt |
| `env/chroot-packages.txt` | inside the Debian 12 root |

## Repository layout

```
build.sh                  build driver (disk preflight, unmount, lb stages)
auto/config               lb config options (mirror, packages, boot params)
auto/build, auto/clean    live-build stage hooks
config/package-lists/     userland package set + firmware
config/hooks/normal/      user, locale/timezone, auto-toram, stripping
config/includes.chroot/   LightDM autologin, Openbox session, tint2 panel
config/bootloaders/       zero-timeout UEFI GRUB config
env/                      bootstrap, mirror selection, gate, reset, chroot shell
test/qemu.sh              UEFI boot test
docs/                     SETUP, BUILD, DECISIONS, HARDWARE, USB
AGENTS.md                 strict build rules (disk, isolation, recovery)
```

## Documentation

| Document | Contents |
|---|---|
| `docs/SETUP.md` | clone → provision → build → test, troubleshooting |
| `docs/BUILD.md` | pipeline internals, invariants, verification matrix |
| `docs/DECISIONS.md` | locked v0.1 design decisions and consequences |
| `docs/HARDWARE.md` | target hardware, firmware requirements, field inventory |
| `docs/USB.md` | writing the stick, Secure Boot, saving student work |

## Status

v0.1 in development. The build pipeline is complete and gated; the ISO has not
yet completed a full build + hardware validation.

## License

MIT — see `LICENSE`.
