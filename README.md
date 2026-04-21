# K1OS - Linux-based Operating System

Language: English (default) | [Русская версия](README.ru.md)

WARP is now developed in the standalone [KEYTRON/WARP](https://github.com/KEYTRON/WARP) repository.
K1OS pulls WARP from that repo during `make warp`.
If you keep both repos side by side, `packages/warp/build.sh` will use the sibling `../WARP` checkout.
You can override that with `WARP_SOURCE_DIR=/path/to/WARP`.

K1OS also publishes a container image to GHCR as `ghcr.io/keytron/k1os`.
The container workflow smoke-tests both the base image and the bundled `warp` package manager.

[![K1OS Container](https://github.com/KEYTRON/K1OS/actions/workflows/k1os-image.yml/badge.svg)](https://github.com/KEYTRON/K1OS/actions/workflows/k1os-image.yml)

Current K1OS-side integration source:
- [`packages/warp/build.sh`](packages/warp/build.sh)
- [`Dockerfile`](Dockerfile)

## Overview

K1OS is a Linux-based operating system focused on development.

The project uses the Linux kernel as a reliable foundation (drivers, scheduler, memory, networking) so we do not spend years building a kernel from scratch. K1OS development is focused on user space, boot flow, tooling, and system integration.

K1OS is not "just another distro clone". It is a standalone operating system built on top of the Linux kernel.

## Core Components

- Linux kernel (`kernel/linux-7.0`) as the base system layer.
- Minimal `initramfs` (stage 1) to initialize early boot and prepare the real root.
- `system.squashfs` as the read-only base rootfs.
- `overlayfs` over squashfs with either:
  - `tmpfs` (RAM mode), or
  - `ext4` partition labeled `K1OS-DATA` (persistent mode).
- `runit` as stage 2 init (`/sbin/init` inside rootfs).
- Built userland: `busybox`, `fish`, `curl`, `git`, `dropbear`, `tmux`, `nano`, `python3`, `htop`.
- `warp` (package manager in C, sourced from the standalone KEYTRON/WARP repo) for package install and management.

## Boot Architecture

1. GRUB loads `vmlinuz` and `initramfs.gz`.
2. Stage 1 (`rootfs/init`) mounts `system.squashfs`.
3. Stage 1 sets up `overlayfs` (persistent or RAM mode).
4. `switch_root` transfers control to `/sbin/init` (stage 2).
5. Stage 2 starts services and the K1OS shell environment.

## Repository Layout

```text
K1OS/
├── kernel/              # Linux kernel source/config
├── rootfs/              # Base rootfs and init scripts
├── packages/            # Userland package builds + warp
├── scripts/             # Build scripts for rootfs/ISO/persist
├── docs/                # Project documentation
├── custom/              # Optional extensions (modules/patches/tools)
├── build/               # Intermediate build artifacts/configs
└── Makefile             # Main build and run targets
```

## Quick Start

```bash
# 1) Kernel
make kernel

# 2) RootFS
make rootfs

# 3) ISO
make iso
```

Full build:

```bash
make all-build
```

QEMU test:

```bash
# RAM mode
make qemu

# persistent storage
make make-persist
make qemu-persist
```

## Additional Docs

- Kernel integration: [`docs/MIGRATION.md`](docs/MIGRATION.md) | [`docs/MIGRATION.ru.md`](docs/MIGRATION.ru.md)
- Custom extensions: [`custom/README.md`](custom/README.md) | [`custom/README.ru.md`](custom/README.ru.md)

## License

Apache License 2.0 - see `LICENSE`.
