# K1OS roadmap

Stage: 1.0.0-alpha.1

Stages go in order: `[x]` is done, `[ ]` is planned. The current stage is the first unfinished one.

## Generation 0: the Linux profile
- [x] ISO on Linux 7.0 with busybox, runit and fish, booted by GRUB
- [x] `system.squashfs` with overlayfs: a persistent partition or RAM mode
- [x] The WARP package manager in the base system
- [x] Container image `ghcr.io/keytron/k1os`
- [x] Disk installer `k1os-install`
- [x] Node.js and Tailscale packages

## Generation 1: booting on our own K1K kernel
- [x] ISO on K1K, BIOS and UEFI boot
- [x] FAT16 disk with services in `/SVC`
- [x] Boot test in CI on the self-hosted K1 lab runners (4 CPUs, NVMe)
- [x] First release, 1.0.0-alpha.1

## Converging the profiles
- [ ] File protocol in K1K so services read files themselves
- [ ] K1OS services delivered to `/SVC` as WARP packages
- [ ] A terminal and shell on K1K
- [ ] Networking on K1K
- [ ] Kernel integration docs (`docs/MIGRATION`) updated for K1K

## Other architectures
K1OS builds only for x86_64 today.
- [ ] An aarch64 image, both on K1K and in the Linux profile
- [ ] WARP packages for aarch64
- [ ] Apple Silicon
- [ ] RISC-V (riscv64) — once there is real hardware to test on

## Later
- [ ] The K1DE graphical environment (postponed until the MVP)
