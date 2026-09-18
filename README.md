# K1OS — Operating System on the K1K kernel

Language: English (default) | [Русская версия](README.ru.md)

[![K1OS on K1K](https://github.com/KEYTRON/K1OS/actions/workflows/k1os-k1k.yml/badge.svg)](https://github.com/KEYTRON/K1OS/actions/workflows/k1os-k1k.yml)
[![K1OS Container](https://github.com/KEYTRON/K1OS/actions/workflows/k1os-image.yml/badge.svg)](https://github.com/KEYTRON/K1OS/actions/workflows/k1os-image.yml)
[![Release](https://img.shields.io/github/v/release/KEYTRON/K1OS?include_prereleases&label=release)](https://github.com/KEYTRON/K1OS/releases)
[![Kernel](https://img.shields.io/badge/kernel-K1K%201.0.0--alpha-blue)](https://github.com/KEYTRON/K1K)
[![WARP](https://img.shields.io/badge/packages-WARP-orange)](https://github.com/KEYTRON/WARP)

Where it boots today (checked by CI on every push, on our own lab runner):

| Target | Kernel | Status |
|--------|--------|--------|
| QEMU q35, BIOS (Limine) | K1K | boot test passes: 4 CPUs, NVMe disk, services from `/SVC` |
| QEMU q35, UEFI (OVMF) | K1K | boot test passes |
| Container (`ghcr.io/keytron/k1os`) | host Linux | smoke test: `fish`, `warp` |
| QEMU, GRUB ISO | Linux 7.0 (legacy profile) | built manually, not in CI |

## What K1OS is

K1OS is our own operating system, and since generation 1 it boots on our own
kernel, **[K1K](https://github.com/KEYTRON/K1K)** — a hybrid, capability-based
kernel written in Rust: a small privileged core (scheduler, memory, IPC,
capabilities) and everything else — drivers, file system, init — as isolated
ring-3 services that a supervisor restarts if they crash. The NVMe driver, the
keyboard driver and the FAT file server already run in ring 3; the kernel
image embeds only those, and the rest of user space is loaded from the disk.

The **Linux profile** (`KERNEL=linux`) is the previous generation: Linux 7.0,
busybox + runit + fish, `system.squashfs` with overlayfs, GRUB. It still builds
and it is what the container image ships, because the K1K user space is young.
The two profiles will converge as K1K grows the services K1OS needs (file
protocol, networking, terminal) and as WARP starts delivering service binaries
to `/SVC`.

Packages come from **[WARP](https://github.com/KEYTRON/WARP)**, our package
manager (C, signed archives, P2P mirrors). K1OS builds it from the sibling
`../WARP` checkout or `WARP_SOURCE_DIR`.

## Build

Requirements for the K1K profile: Rust nightly via `rustup` (the K1K checkout
pins the exact toolchain), `xorriso`, `mtools`, `qemu-system-x86_64`, `make`,
`git`, and the K1K sources — a sibling `../K1K` checkout or `K1K_SOURCE_DIR`.

```bash
make kernel      # build K1K (release) into build/k1k/
make iso         # Limine ISO with K1OS branding: build/k1k/k1os-k1k.iso
make disk        # FAT16 service disk (NVMe): build/k1k/k1os-k1k-disk.img
make test        # boot the ISO headless in QEMU and check the log
make qemu        # interactive QEMU (KVM, 4 CPUs, serial on stdio)
```

Legacy Linux profile:

```bash
make KERNEL=linux kernel rootfs iso   # hours: compiles the whole userland
make KERNEL=linux qemu
make image                            # container image from the prebuilt rootfs
```

## Boot architecture (K1K profile)

1. Limine loads the K1K kernel (`/boot/k1k` on the ISO), BIOS or UEFI.
2. The kernel brings up memory, SMP, ACPI/APIC and starts its embedded
   services: `kbd`, `blk` (NVMe), `fs`, plus the `ping`/`pong` IPC demo.
3. `fs` mounts the FAT16 volume on the NVMe disk through `blk` and `spawn`s
   every ELF in `/SVC` as a supervised service.
4. A crashed service is torn down and restarted from its image — no reboot.

Legacy profile: GRUB → `vmlinuz` + `initramfs.gz` → `system.squashfs` +
overlayfs (`tmpfs` or the `K1OS-DATA` ext4 partition) → `switch_root` → runit.

## Repository layout

```text
K1OS/
├── scripts/build-k1k.sh # K1K profile: sync kernel sources, build, ISO, disk, test
├── ci/runner/           # self-hosted lab runners (Docker) used by all K1 repos
├── kernel/              # Linux kernel source/config (legacy profile)
├── rootfs/              # Linux rootfs and init scripts (legacy profile, container)
├── packages/            # Userland package builds + warp
├── scripts/             # Build scripts for rootfs/ISO/persist
├── docs/                # Project documentation
├── custom/              # Optional extensions (modules/patches/tools)
├── build/               # Build artifacts (build/k1k/ for the K1K profile)
├── VERSION              # K1OS version
└── Makefile             # Main build and run targets (KERNEL=k1k|linux)
```

## CI and releases

All workflows run on the self-hosted **K1 lab runners** (`ci/runner/`):
GitHub's hosted runners cannot boot our OS and every job there costs minutes.
The runners have KVM, Docker, Rust and read-only access to the lab checkouts,
which is how K1OS builds the private K1K repository.

- `K1OS on K1K` — builds the kernel, ISO and disk, boot-tests them, uploads
  the media as artifacts; on a `v*` tag it publishes a GitHub release.
- `K1OS Container` — builds the container from the prebuilt rootfs and pushes
  `ghcr.io/keytron/k1os`.

## Additional docs

- Kernel integration: [`docs/MIGRATION.md`](docs/MIGRATION.md) | [`docs/MIGRATION.ru.md`](docs/MIGRATION.ru.md)
- Custom extensions: [`custom/README.md`](custom/README.md) | [`custom/README.ru.md`](custom/README.ru.md)
- Lab runners: [`ci/runner/README.md`](ci/runner/README.md)

## License

Apache License 2.0 — see `LICENSE`.
