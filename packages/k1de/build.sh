#!/bin/bash
# Build k1de for K1OS

set -e

PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${PKG_DIR}/../.." && pwd)"
ROOTFS_DIR="${ROOT_DIR}/rootfs"
BUILD_DIR="${PKG_DIR}/target/release"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[k1de]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[k1de]${NC} $1"; }
log_error() { echo -e "${RED}[k1de]${NC} $1"; }

build() {
    log_info "Building k1de package in release mode..."
    cargo build --manifest-path "${PKG_DIR}/Cargo.toml" --release
}

pkg_install() {
    log_info "Installing k1de to rootfs..."
    install -Dm755 "${BUILD_DIR}/k1de" "${ROOTFS_DIR}/usr/bin/k1de"
    log_info "k1de installed: /usr/bin/k1de"
}

case "${1:-all}" in
    build)   build ;;
    install) build && pkg_install ;;
    all)     build && pkg_install ;;
    clean)
        log_info "Cleaning k1de build..."
        cargo clean --manifest-path "${PKG_DIR}/Cargo.toml"
        ;;
    *)
        echo "Usage: $0 [build|install|all|clean]"
        exit 1
        ;;
esac
