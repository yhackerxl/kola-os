# Hardware target

## Minimum / recommended

| Profile | RAM | Storage | Boot | Expected experience |
|---|---|---|---|---|
| Absolute minimum | 512 MB | none | USB 2.0 | Openbox + editor + files; browser unusable |
| Practical | 1 GB | none | USB 2.0 | Desktop + browser with 1–2 tabs |
| Recommended | 2 GB | none | USB 3.0 | Full session in RAM (`toram`), USB removable after boot |

Diskless operation is native: the root filesystem is a squashfs on the USB
stick, all writes go to a tmpfs overlay and are discarded on power-off.

## Firmware requirements

- 64-bit UEFI.
- **Secure Boot OFF.**
- USB boot enabled.

## Capture this data per school

Before v0.2 scoping, collect:

```
CPU model:        dmidecode -s processor-version
RAM installed:    dmidecode -t memory | grep -i "size:"
Firmware mode:    ls /sys/firmware/efi   (present = UEFI)
Secure Boot:      mokutil --sb-state
Wi-Fi chipset:    lspci -nn | grep -i network
GPU:              lspci -nn | grep -i -E 'vga|3d'
```

Reason: if the inventory turns out to be predominantly 32-bit or BIOS-only, the
architecture decision (item 2) has to be revisited before v0.2.
