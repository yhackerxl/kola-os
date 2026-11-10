# Kola OS — Locked Decisions (v0.1)

| # | Topic | Decision |
|---|---|---|
| 1 | Memory strategy | `toram` automatically when RAM ≥ **1600 MB**, otherwise normal USB boot. Threshold is a build-time variable (`KOLA_TORAM_MIN_MB`). |
| 2 | Architecture / firmware | `amd64`, **UEFI only**. BIOS support deferred; no i386, no 32-bit UEFI. |
| 3 | Boot splash | Silent boot **removed**. `quiet loglevel=3`, no Plymouth. A "safe graphics" GRUB entry exists for broken GPUs. |
| 4 | Session | LightDM → Openbox, autologin, no password, passwordless sudo. |
| 5 | Applications | LXTerminal, PCManFM, Geany, Epiphany, **LXTask** (RAM/process monitor). Nothing else. |
| 6 | Wi-Fi | `network-manager` + `nm-applet` in the tint2 systray. `non-free-firmware` enabled for Intel/Realtek/Atheros/Broadcom. |
| 7 | Audio | Enabled, **ALSA only** — no PulseAudio/PipeWire daemon (saves ~40–60 MB). Volume via `volumeicon-alsa`. |
| 8 | Clock | `systemd-timesyncd` enabled, TZ `Africa/Dar_es_Salaam`. |
| 9 | Keyboard / locale | `pc105`, layout `us`; `en_US.UTF-8` UI, `sw_TZ.UTF-8` generated. |
| 10 | Printing | Excluded. CUPS not installed, not recoverable at runtime. |
| 11 | Build environment | Isolated Debian 12 chroot at `~/.cache/kola-buildroot`. **No Docker.** |
| 12 | APT pinning | Rolling `bookworm` (reproducible builds via snapshot deferred). |
| 13 | License | MIT. |
| 14 | Education payload | None in v0.1. |
| 15 | Testing | QEMU + OVMF at 1024 MB (non-toram) and 2048 MB (toram). |

## Consequences to keep in mind

- **Secure Boot must be disabled** on target machines. Debian's GRUB in a
  `live-build` ISO is unsigned; signed shim support is not part of v0.1.
- Epiphany sets the real memory floor. Desktop idle is ~350 MB; a browser session
  reaches ~700–900 MB. 512 MB machines boot and run the file manager/editor but
  will swap-thrash with the browser.
- Because `--apt-recommends false` is global, every runtime dependency is listed
  explicitly in `config/package-lists/`. Adding a package means checking its
  recommends manually.
