#!/bin/bash
# Build K1OS bootable ISO image
# Requires: kernel build + rootfs build to be done first

set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS_DIR="${ROOT_DIR}/rootfs"
ISO_DIR="${ROOT_DIR}/iso"
KERNEL_SRC="${ROOT_DIR}/kernel/linux-6.17.9"
OUTPUT="${ROOT_DIR}/k1os.iso"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[iso]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[iso]${NC} $1"; }
log_error() { echo -e "${RED}[iso]${NC} $1"; }

check_deps() {
    local missing=()
    for dep in xorriso mksquashfs; do
        command -v "$dep" &>/dev/null || missing+=("$dep")
    done
    # grub-mkrescue может называться grub2-mkrescue на Fedora
    if ! command -v grub-mkrescue &>/dev/null && ! command -v grub2-mkrescue &>/dev/null; then
        missing+=("grub-mkrescue/grub2-mkrescue")
    fi
    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing dependencies: ${missing[*]}"
        log_warn "Install with: sudo dnf install grub2-tools-extra xorriso squashfs-tools"
        exit 1
    fi
}

# Определяем имя команды grub-mkrescue
GRUB_MKRESCUE="$(command -v grub2-mkrescue 2>/dev/null || command -v grub-mkrescue 2>/dev/null)"

check_kernel() {
    if [ ! -f "${KERNEL_SRC}/arch/x86/boot/bzImage" ]; then
        log_error "Kernel not built. Run: make kernel"
        exit 1
    fi
}

check_rootfs() {
    if [ ! -f "${ROOTFS_DIR}/sbin/init" ]; then
        log_error "rootfs not ready. Run: scripts/build-rootfs.sh"
        exit 1
    fi
}

build_initramfs() {
    log_info "Building initramfs..."
    cd "${ROOTFS_DIR}"
    find . | cpio -oH newc 2>/dev/null | gzip -9 > "${ISO_DIR}/boot/initramfs.gz"
    cd "${ROOT_DIR}"
    log_info "initramfs size: $(du -sh ${ISO_DIR}/boot/initramfs.gz | cut -f1)"
}

setup_iso_tree() {
    log_info "Setting up ISO directory tree..."
    mkdir -p "${ISO_DIR}/boot/grub"

    # Copy kernel
    cp "${KERNEL_SRC}/arch/x86/boot/bzImage" "${ISO_DIR}/boot/vmlinuz"

    # GRUB config
    cat > "${ISO_DIR}/boot/grub/grub.cfg" << 'EOF'
set default=0
set timeout=3

menuentry "K1OS" {
    linux /boot/vmlinuz root=/dev/ram0 rw console=tty0 console=ttyS0,115200 quiet
    initrd /boot/initramfs.gz
}

menuentry "K1OS (debug)" {
    linux /boot/vmlinuz root=/dev/ram0 rw console=tty0 console=ttyS0,115200
    initrd /boot/initramfs.gz
}
EOF
}

build_iso() {
    log_info "Building ISO image..."
    "${GRUB_MKRESCUE}" -o "${OUTPUT}" "${ISO_DIR}" -- -volid K1OS 2>/dev/null
    log_info "ISO created: ${OUTPUT}"
    log_info "Size: $(du -sh ${OUTPUT} | cut -f1)"
}

print_test_cmd() {
    echo ""
    log_info "Test in QEMU:"
    echo "  qemu-system-x86_64 -m 512M -cdrom ${OUTPUT} -nographic"
    echo "  qemu-system-x86_64 -m 512M -cdrom ${OUTPUT} -vga virtio"
    echo ""
}

main() {
    check_deps
    check_kernel
    check_rootfs
    setup_iso_tree
    build_initramfs
    build_iso
    print_test_cmd
}

main "$@"
