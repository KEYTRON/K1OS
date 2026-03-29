#!/bin/bash
# Build K1OS bootable ISO image
# Architecture: minimal initramfs → squashfs (overlayfs) → switch_root → runit

set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS_DIR="${ROOT_DIR}/rootfs"
ISO_DIR="${ROOT_DIR}/iso"
KERNEL_SRC="${ROOT_DIR}/kernel/linux-6.19.10"
OUTPUT="${ROOT_DIR}/k1os.iso"
INITRAMFS_TMP="${ROOT_DIR}/build/initramfs_tmp"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[iso]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[iso]${NC} $1"; }
log_error() { echo -e "${RED}[iso]${NC} $1"; }

check_deps() {
    local missing=()
    for dep in xorriso mksquashfs; do
        command -v "$dep" &>/dev/null || missing+=("$dep")
    done
    if ! command -v grub-mkrescue &>/dev/null && ! command -v grub2-mkrescue &>/dev/null; then
        missing+=("grub-mkrescue/grub2-mkrescue")
    fi
    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing dependencies: ${missing[*]}"
        log_warn "Install with: sudo dnf install grub2-tools-extra xorriso squashfs-tools"
        exit 1
    fi
}

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

# Минимальный initramfs: busybox + init скрипт
# Всё остальное живёт в squashfs
build_initramfs() {
    log_info "Building minimal initramfs..."
    rm -rf "${INITRAMFS_TMP}"
    mkdir -p "${INITRAMFS_TMP}"/{bin,dev,proc,sys,run,newroot,mnt/boot}

    # Копируем статически слинкованный busybox
    if [ -f "${ROOTFS_DIR}/bin/busybox" ]; then
        cp "${ROOTFS_DIR}/bin/busybox" "${INITRAMFS_TMP}/bin/busybox"
        chmod +x "${INITRAMFS_TMP}/bin/busybox"
    else
        log_error "busybox not found in rootfs/bin/"
        exit 1
    fi

    # Создаём симлинки на нужные утилиты
    for tool in sh mount umount mkdir echo cat switch_root findfs mdev \
                modprobe insmod ln cp rm ls sleep; do
        ln -sf busybox "${INITRAMFS_TMP}/bin/${tool}"
    done
    mkdir -p "${INITRAMFS_TMP}/sbin"
    for tool in switch_root findfs mdev blkid; do
        ln -sf ../bin/busybox "${INITRAMFS_TMP}/sbin/${tool}"
    done

    # Копируем init скрипт
    cp "${ROOTFS_DIR}/init" "${INITRAMFS_TMP}/init"
    chmod +x "${INITRAMFS_TMP}/init"

    # Собираем cpio + gzip
    (cd "${INITRAMFS_TMP}" && find . | cpio -oH newc 2>/dev/null | gzip -9) \
        > "${ISO_DIR}/boot/initramfs.gz"
    log_info "initramfs size: $(du -sh ${ISO_DIR}/boot/initramfs.gz | cut -f1)"
}

# Полный rootfs упаковываем в squashfs
build_squashfs() {
    log_info "Building system.squashfs..."
    # Исключаем init из squashfs — он нужен только в initramfs
    mksquashfs "${ROOTFS_DIR}" "${ISO_DIR}/system.squashfs" \
        -comp xz -Xdict-size 100% \
        -noappend \
        -no-xattrs \
        -e "${ROOTFS_DIR}/init" \
        2>/dev/null
    log_info "squashfs size: $(du -sh ${ISO_DIR}/system.squashfs | cut -f1)"
}

setup_iso_tree() {
    log_info "Setting up ISO directory tree..."
    mkdir -p "${ISO_DIR}/boot/grub"

    cp "${KERNEL_SRC}/arch/x86/boot/bzImage" "${ISO_DIR}/boot/vmlinuz"

    cat > "${ISO_DIR}/boot/grub/grub.cfg" << 'EOF'
set default=0
set timeout=3

menuentry "K1OS" {
    linux /boot/vmlinuz root=/dev/ram0 rw console=tty0 console=ttyS0,115200 quiet
    initrd /boot/initramfs.gz
}

menuentry "K1OS (RAM mode, no persist)" {
    linux /boot/vmlinuz root=/dev/ram0 rw console=tty0 console=ttyS0,115200 nopersist
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
    log_info "Test in QEMU (RAM mode):"
    echo "  qemu-system-x86_64 -m 512M -cdrom ${OUTPUT} -vga virtio -enable-kvm"
    echo ""
    log_info "Test with persistent storage:"
    echo "  qemu-img create -f qcow2 persist.qcow2 2G"
    echo "  # Разметить: make-persist persist.qcow2"
    echo "  qemu-system-x86_64 -m 512M -cdrom ${OUTPUT} -hda persist.qcow2 -vga virtio -enable-kvm"
    echo ""
}

main() {
    check_deps
    check_kernel
    check_rootfs
    setup_iso_tree
    build_squashfs
    build_initramfs
    build_iso
    print_test_cmd
}

main "$@"
