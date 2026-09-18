#!/bin/bash
# Build K1OS boot media on the K1K kernel.
#
# The kernel lives in its own repository (KEYTRON/K1K). We take it from
# K1K_SOURCE_DIR (default: sibling ../K1K checkout, or clone K1K_REPO_URL),
# copy the sources out of tree so a read-only checkout works, build the
# release kernel + services with K1K's own Makefile, and produce:
#
#   build/k1k/k1os-k1k.iso        Limine ISO (BIOS + UEFI) with K1OS branding
#   build/k1k/k1os-k1k-disk.img   FAT16 image with /SVC services (NVMe drive)
#   build/k1k/k1k.elf             the kernel
#
# Usage: build-k1k.sh [kernel|iso|disk|test|all]

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${ROOT_DIR}/build/k1k"
SRC_DIR="${OUT_DIR}/src"
K1K_SOURCE_DIR="${K1K_SOURCE_DIR:-}"
K1K_REPO_URL="${K1K_REPO_URL:-https://github.com/KEYTRON/K1K.git}"
K1K_REPO_REF="${K1K_REPO_REF:-main}"
QEMUFLAGS="${QEMUFLAGS:--m 512M -smp 4}"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[k1k]${NC} $1"; }
warn() { echo -e "${YELLOW}[k1k]${NC} $1"; }
die()  { echo -e "${RED}[k1k]${NC} $1"; exit 1; }

find_source() {
    if [ -n "${K1K_SOURCE_DIR}" ] && [ -f "${K1K_SOURCE_DIR}/kernel/Cargo.toml" ]; then
        echo "$(cd "${K1K_SOURCE_DIR}" && pwd)"
        return
    fi
    if [ -f "${ROOT_DIR}/../K1K/kernel/Cargo.toml" ]; then
        echo "$(cd "${ROOT_DIR}/../K1K" && pwd)"
        return
    fi
    if [ ! -d "${OUT_DIR}/clone/.git" ]; then
        log "Cloning ${K1K_REPO_URL} (${K1K_REPO_REF})" >&2
        git clone --depth=1 --branch "${K1K_REPO_REF}" "${K1K_REPO_URL}" "${OUT_DIR}/clone" >&2 \
            || die "K1K source not found: set K1K_SOURCE_DIR or keep a ../K1K checkout"
    fi
    echo "${OUT_DIR}/clone"
}

sync_source() {
    local src; src="$(find_source)"
    mkdir -p "${SRC_DIR}"
    log "Syncing K1K sources from ${src}"
    rsync -a --delete \
        --exclude '/kernel/target' --exclude '/user/target' --exclude '/build' \
        --exclude '/.git' \
        "${src}/" "${SRC_DIR}/"
    (cd "${src}" && git rev-parse --short HEAD 2>/dev/null || echo unknown) > "${OUT_DIR}/K1K_COMMIT"
    grep -m1 '^version' "${SRC_DIR}/kernel/Cargo.toml" | sed 's/.*"\(.*\)"/\1/' > "${OUT_DIR}/K1K_VERSION"
    log "K1K $(cat "${OUT_DIR}/K1K_VERSION") @ $(cat "${OUT_DIR}/K1K_COMMIT")"
}

k1k_make() {
    make -C "${SRC_DIR}" PROFILE=release "$@"
}

build_kernel() {
    sync_source
    log "Building kernel and services (release)"
    k1k_make kernel
    cp "${SRC_DIR}/kernel/target/x86_64-unknown-none/release/k1k" "${OUT_DIR}/k1k.elf"
}

build_iso() {
    [ -f "${OUT_DIR}/k1k.elf" ] || build_kernel
    log "Building Limine ISO"
    k1k_make limine
    cat > "${OUT_DIR}/limine.conf" <<EOF
timeout: 3
serial: yes
verbose: no
interface_branding: K1OS $(cat "${ROOT_DIR}/VERSION" 2>/dev/null || echo dev) / K1K $(cat "${OUT_DIR}/K1K_VERSION")

/K1OS (K1K kernel)
    protocol: limine
    path: boot():/boot/k1k
    kaslr: no

/K1OS (K1K kernel, autotest)
    protocol: limine
    path: boot():/boot/k1k
    kaslr: no
    cmdline: autotest
EOF
    (cd "${SRC_DIR}" && sh tools/mkiso.sh "${OUT_DIR}/k1k.elf" "${OUT_DIR}/limine.conf" "${OUT_DIR}/k1os-k1k.iso")
    log "ISO: ${OUT_DIR}/k1os-k1k.iso ($(du -sh "${OUT_DIR}/k1os-k1k.iso" | cut -f1))"
}

build_disk() {
    [ -f "${OUT_DIR}/k1k.elf" ] || build_kernel
    log "Building FAT16 service disk"
    k1k_make disk
    cp "${SRC_DIR}/build/disk.img" "${OUT_DIR}/k1os-k1k-disk.img"
    printf 'K1OS on K1K %s (%s) - services under /SVC are started by fs at boot\n' \
        "$(cat "${OUT_DIR}/K1K_VERSION")" "$(cat "${OUT_DIR}/K1K_COMMIT")" > "${OUT_DIR}/README.TXT"
    mcopy -o -i "${OUT_DIR}/k1os-k1k-disk.img" "${OUT_DIR}/README.TXT" ::/README.TXT
    log "Disk: ${OUT_DIR}/k1os-k1k-disk.img"
}

# Boot the K1OS ISO's autotest entry headless; K1K exits QEMU with 33 on success.
run_test() {
    [ -f "${OUT_DIR}/k1os-k1k.iso" ] || build_iso
    [ -f "${OUT_DIR}/k1os-k1k-disk.img" ] || build_disk
    log "Boot test in QEMU"
    sed 's/^timeout: 3/timeout: 0\ndefault_entry: 2/' "${OUT_DIR}/limine.conf" > "${OUT_DIR}/limine-test.conf"
    (cd "${SRC_DIR}" && sh tools/mkiso.sh "${OUT_DIR}/k1k.elf" "${OUT_DIR}/limine-test.conf" "${OUT_DIR}/k1os-k1k-test.iso")
    local kvm=""
    [ -w /dev/kvm ] && kvm="-enable-kvm -cpu host"
    set +e
    timeout 120 qemu-system-x86_64 -M q35 ${kvm} -cdrom "${OUT_DIR}/k1os-k1k-test.iso" -boot d \
        -display none -serial "file:${OUT_DIR}/serial.log" -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        -drive "file=${OUT_DIR}/k1os-k1k-disk.img,if=none,format=raw,id=nvme0" \
        -device nvme,drive=nvme0,serial=K1OS-NVME-0001 ${QEMUFLAGS}
    local status=$?
    set -e
    tail -n 25 "${OUT_DIR}/serial.log"
    [ "$status" -eq 33 ] || die "boot test failed (qemu exit ${status})"
    grep -q 'fs\] spawned HELLO.ELF' "${OUT_DIR}/serial.log" || die "fs did not start services from /SVC"
    log "Boot test passed"
}

mkdir -p "${OUT_DIR}"
case "${1:-all}" in
    kernel) build_kernel ;;
    iso)    build_iso ;;
    disk)   build_disk ;;
    test)   run_test ;;
    all)    build_kernel; build_iso; build_disk; run_test ;;
    *)      die "unknown step: $1" ;;
esac
