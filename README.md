# Kola OS

Ultra-lightweight Debian 12 live distribution for Tanzanian secondary schools.
Boots from USB, runs in RAM when memory allows, no hard drive required.

- Base: Debian 12 (Bookworm), amd64, UEFI
- Session: LightDM (autologin) → Openbox
- Tools: LXTerminal, PCManFM, Geany, Epiphany, LXTask
- Policy: zero bloat, `--apt-recommends false`, no printing, no persistence

## Build model

`live-build` must run as root on Debian 12. The host (Pop!_OS/Ubuntu) is **never**
used as the build root. Everything happens inside a dedicated Debian 12 chroot at
`~/.cache/kola-buildroot`; the repo is bind-mounted at `/build`.

```
./env/bootstrap.sh     # one-time per machine: host tools + shared Debian 12 root
./env/verify.sh        # gate: must PASS before any build
make build             # lb config + lb build inside the chroot
make test              # boot the ISO in QEMU/OVMF
make clean
```

The build root lives at `~/.cache/debian12-live-build` and is **shared across
projects**; a new project only needs `KOLA_BUILDROOT` set to it (the default).
Nothing is installed per-project.

Output: `kola-os-*.iso` in the repo root.

## Requirements

Host packages: `mmdebstrap` (or `debootstrap`), `qemu-system-x86`, `ovmf`.
Nothing else from the host leaks into the image.

## Known risk points

See `docs/BUILD.md` — the GRUB zero-timeout override and the auto-`toram`
initramfs patch are the two components that must be verified on the first build.

## License

MIT — see `LICENSE`.
