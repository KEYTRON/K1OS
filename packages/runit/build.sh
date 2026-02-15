#!/bin/bash
# Build runit for K1OS init system
# runit: simple, fast, reliable init & process supervision

set -e

RUNIT_VERSION="2.2.0"
RUNIT_URL="http://smarden.org/runit/runit-${RUNIT_VERSION}.tar.gz"
PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${PKG_DIR}/../.." && pwd)"
ROOTFS_DIR="${ROOT_DIR}/rootfs"
BUILD_DIR="${PKG_DIR}/build"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[runit]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[runit]${NC} $1"; }
log_error() { echo -e "${RED}[runit]${NC} $1"; }

fetch() {
    if [ ! -f "${PKG_DIR}/runit-${RUNIT_VERSION}.tar.gz" ]; then
        log_info "Downloading runit ${RUNIT_VERSION}..."
        wget -q --show-progress "${RUNIT_URL}" -O "${PKG_DIR}/runit-${RUNIT_VERSION}.tar.gz"
    else
        log_info "runit source already downloaded"
    fi

    if [ ! -d "${BUILD_DIR}" ]; then
        log_info "Extracting runit..."
        mkdir -p "${BUILD_DIR}"
        tar -xzf "${PKG_DIR}/runit-${RUNIT_VERSION}.tar.gz" -C "${BUILD_DIR}" --strip-components=2
    fi
}

build() {
    log_info "Building runit..."
    # runit uses package/compile build system
    cd "${BUILD_DIR}"
    package/compile
}

install() {
    log_info "Installing runit to rootfs..."
    install -Dm755 "${BUILD_DIR}/command/runit"         "${ROOTFS_DIR}/sbin/runit"
    install -Dm755 "${BUILD_DIR}/command/runit-init"    "${ROOTFS_DIR}/sbin/runit-init"
    install -Dm755 "${BUILD_DIR}/command/runsvdir"      "${ROOTFS_DIR}/sbin/runsvdir"
    install -Dm755 "${BUILD_DIR}/command/runsv"         "${ROOTFS_DIR}/sbin/runsv"
    install -Dm755 "${BUILD_DIR}/command/sv"            "${ROOTFS_DIR}/sbin/sv"
    install -Dm755 "${BUILD_DIR}/command/chpst"         "${ROOTFS_DIR}/sbin/chpst"
    install -Dm755 "${BUILD_DIR}/command/utmpset"       "${ROOTFS_DIR}/sbin/utmpset"
    install -Dm755 "${BUILD_DIR}/command/svlogd"        "${ROOTFS_DIR}/sbin/svlogd"

    log_info "Setting up runit service directories..."
    mkdir -p "${ROOTFS_DIR}/etc/runit"
    mkdir -p "${ROOTFS_DIR}/etc/sv"
    mkdir -p "${ROOTFS_DIR}/var/service"

    # Copy runit stage scripts
    install -Dm755 "${PKG_DIR}/scripts/1" "${ROOTFS_DIR}/etc/runit/1"
    install -Dm755 "${PKG_DIR}/scripts/2" "${ROOTFS_DIR}/etc/runit/2"
    install -Dm755 "${PKG_DIR}/scripts/3" "${ROOTFS_DIR}/etc/runit/3"

    log_info "runit installed"
}

case "${1:-all}" in
    fetch)   fetch ;;
    build)   fetch && build ;;
    install) fetch && build && install ;;
    all)     fetch && build && install ;;
    clean)
        log_info "Cleaning runit build..."
        rm -rf "${BUILD_DIR}"
        ;;
    *)
        echo "Usage: $0 [fetch|build|install|all|clean]"
        exit 1
        ;;
esac
