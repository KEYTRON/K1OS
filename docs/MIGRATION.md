# Linux Kernel Integration Guide

Language: English (default) | [Русская версия](MIGRATION.ru.md)

> This file is still named `MIGRATION.md` for backward compatibility.
> It now documents Linux kernel integration in K1OS, not a one-time migration effort.

## K1OS Positioning

K1OS is a Linux-based operating system.

Linux kernel is used as the base system layer so we can:
- avoid spending years on writing a new kernel from scratch;
- rely on mature kernel subsystems and driver support;
- focus K1OS engineering effort on boot flow, rootfs, user space, and tooling.

## Responsibilities: Kernel vs K1OS

Linux kernel layer:
- hardware and driver management;
- scheduler, memory, networking, and system interfaces.

K1OS layer:
- boot architecture (`initramfs -> squashfs -> overlayfs -> switch_root`);
- rootfs and userland composition;
- package management via `warp` fetched from the standalone `KEYTRON/WARP` repo during `make warp`;
- ISO build and delivery pipeline.

If `K1OS` and `WARP` are checked out side by side, `packages/warp/build.sh` will use the sibling `../WARP` repo first. Set `WARP_SOURCE_DIR` to override that path.

## Current Integration Flow

### 1. Kernel Maintenance
- Update/pin kernel version in `kernel/`.
- Keep changes minimal relative to upstream.
- Validate required options for K1OS (for example squashfs/overlayfs/block device support).

### 2. Boot Pipeline Integration
- Stage 1 (`rootfs/init`) mounts virtual filesystems and locates `system.squashfs`.
- Stage 1 configures `overlayfs` with either:
  - persistent `ext4` partition (label `K1OS-DATA`), or
  - `tmpfs` for RAM mode.
- `switch_root` transfers control to stage 2 (`/sbin/init`).

### 3. User Space and Packages
- User space components are built through `packages/*/build.sh`.
- Base utilities are assembled into `rootfs/`.
- `warp` is used as the native K1OS package manager and is built from the standalone `KEYTRON/WARP` repository.

### 4. Validation
- Validate ISO boot in both RAM and persistent modes.
- Validate service startup and shell environment.
- Ensure changes do not break boot path or rootfs compatibility.

## Build Commands

```bash
# Kernel
make kernel

# RootFS + packages
make rootfs

# ISO
make iso

# Full build
make all-build

# QEMU (RAM / persistent)
make qemu
make make-persist
make qemu-persist
```

## Kernel Change Rules

- Patch the kernel only when needed for K1OS-specific goals.
- Every kernel change must document rationale and boot/user space impact.
- Prefer upstream-aligned configuration and integration over a deep kernel fork.

## License

The project uses Apache License 2.0. New code and dependencies must be license-compatible.
