# AGENTS.md — Kola OS build rules (STRICT)

These rules are mandatory for any agent or human operating this repository.

## 1. Disk pre-flight (mandatory, before every build)

```bash
df -h / | awk 'NR==2 {print $4}'   # abort if < 20 GB
```

Implemented in `build.sh` (`MIN_FREE_GB=20`, hard abort) and in `env/verify.sh`.

## 2. Isolated workspace

- Never build in `$HOME` directly.
- Build output lives inside this repository (`chroot/`, `cache/`, `binary/`, `.build/`).
- The shared toolchain lives at `~/.cache/debian12-live-build` (a Debian 12
  chroot, not a workspace).

## 3. Clean before build

`lb clean --purge` **must run inside the Debian 12 chroot**, not on the host:

- `lb` is not installed on the host (Pop!_OS/Ubuntu) and would use the wrong
  templates.
- Host-side stale mounts are removed first (`env/reset.sh`, `build.sh` trap).

Implemented in `build.sh` (after unmounting stale `chroot/{proc,sys,dev}`) and
available standalone via `make reset`.

## 4. Package bloat

- `--apt-recommends false` — mandatory, present in `auto/config`.
- `--cache false` — **DO NOT USE HERE.** live-build forces
  `LB_CACHE_STAGES=bootstrap` when `LB_CACHE=false`, which re-enables the
  bootstrap cache copy that fails on the live procfs mounted inside `chroot/`.
  The correct equivalent is `--cache-stages none` (already set). Package `.deb`
  caching remains enabled on purpose: it makes retries cheap.

## 5. Failure recovery

```bash
make reset
```

which performs:

1. `umount -l chroot/{proc,sys,dev/pts,dev}`
2. `lb clean --purge` inside the chroot
3. `rm -rf chroot cache .build`
4. moves `*.log` to `logs/` (kept for diagnosis; never deleted silently)

Never delete logs as part of recovery — they are the only evidence of the failure.

## 6. Gate

`make build` runs `env/verify.sh` first. Any FAIL aborts the build.
