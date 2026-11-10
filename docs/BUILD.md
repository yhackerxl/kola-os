# Build notes

## Pipeline

```
env/bootstrap.sh  ->  ~/.cache/debian12-live-build (Debian 12, mmdebstrap)
env/verify.sh     ->  pre-build gate: host tools, OVMF, KVM, disk, chroot, syntax
env/enter.sh      ->  bind-mount repo at /build, chroot, run build.sh
build.sh          ->  lb clean -> lb config -> auto/config -> lb build
                  ->  kola-os-*.iso + .sha256
```

The build root is **outside the repo and shared**: a new project reuses the same
Debian 12 toolchain by pointing `KOLA_BUILDROOT` at it (default
`~/.cache/debian12-live-build`). Host (Pop!_OS) is used only to host the chroot.
`live-build` never sees the host root filesystem.

`make build` runs `env/verify.sh` first and aborts on any failure.

## Components that MUST be verified on the first build

1. **`config/bootloaders/grub-efi/grub.cfg`** — custom zero-timeout config.
   Assumes Debian live layout `/live/vmlinuz` and `/live/initrd.img`. If the ISO
   uses versioned filenames only, replace with the generated entries or add
   symlinks via a binary hook. Symptom: GRUB menu appears but any entry drops to
   a `grub>` prompt.
2. **Auto-toram initramfs patch** — `0300-kola-auto-toram.hook.chroot` inserts a
   memory check after `TORAM=` initialisation in live-boot's script. The hook
   fails the build if the anchor is missing (upstream layout change). Verify by
   booting QEMU with 2048 MB and checking `dmesg | grep KOLA`; `mount | grep
   /root` should show a tmpfs-backed root when toram is active.
3. **GRUB timeout** — must be `0`. If the menu stalls for 5 s, another
   bootloader config won the copy.

## Verification matrix

| RAM | Expected path | Check |
|---|---|---|
| 1024 MB | no toram | root device is `/dev/loop*` from USB, desktop reachable |
| 2048 MB | toram | root is tmpfs, USB can be unplugged, `free -m` shows ~ISO size consumed |
| 1024 MB + `nomodeset` | safe graphics | X starts on legacy GPUs |

## Known limits

- No persistence: student work must be saved to USB via PCManFM.
- Secure Boot must be disabled.
- Epiphany is the dominant memory consumer; there is no lighter fallback in v0.1.
