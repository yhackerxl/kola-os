# Writing the Kola OS USB stick

## 1. Verify the download

```bash
sha256sum -c kola-os-0.1-amd64.iso.sha256
```

## 2. Write it

### Windows (teachers / school lab)

1. Download **Rufus** (portable, no install): <https://rufus.ie>
2. Select the USB stick (8 GB minimum, contents will be erased).
3. Select the Kola OS ISO.
4. Partition scheme: **GPT**. Target system: **UEFI (non-CSM)**.
5. Start, accept the two warnings about ISOHybrid.

Balena Etcher works too but is ~150 MB; Rufus is preferred for offline labs.

### Linux

```bash
lsblk                                  # find the stick, e.g. /dev/sdb
sudo dd if=kola-os-0.1-amd64.iso of=/dev/sdb bs=4M status=progress oflag=sync
sync
```

`of=/dev/sdX` (the whole device) — **not** `/dev/sdX1`.

## 3. Firmware settings on the target machine

| Setting | Value |
|---|---|
| Boot mode | UEFI |
| Secure Boot | **Disabled** (the ISO is unsigned) |
| USB boot | Enabled |
| Fast Boot | Disabled (otherwise USB is skipped) |

## 4. First boot expectations

- No menu: GRUB timeout is 0 and boots straight in.
- Login prompt is skipped: LightDM autologins `kola` and starts Openbox.
- ≥1600 MB RAM → system copied to RAM, the stick can be removed after boot.
- <1600 MB RAM → system runs from the stick, keep it inserted.

## 5. Saving student work

There is **no persistence** in v0.1. Anything saved outside a USB storage device
is lost on power-off. Workflow for students:

1. Plug a second USB stick.
2. PCManFM → the stick appears in the left pane (udisks2 mounts it).
3. Save there, then unmount before pulling it out.

## Troubleshooting

| Symptom | Cause |
|---|---|
| Boots to firmware menu, USB not listed | Secure Boot on, or Fast Boot on |
| `grub>` prompt | GRUB config/live path mismatch — see `docs/BUILD.md` |
| Black screen after GRUB | GPU/modesetting — choose "safe graphics" entry (requires menu, timeout 0 hides it: hold Shift) |
| Wi-Fi icon present, no networks | `wpasupplicant` or firmware missing |
| No sound | `alsa-ucm-conf` missing, or muted: `alsamixer` |
