#!/bin/bash
# Build/Install Node.js for K1OS

set -e

NODE_VERSION="20.14.0"
NODE_URL="https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz"
PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${PKG_DIR}/../.." && pwd)"
ROOTFS_DIR="${ROOT_DIR}/rootfs"
BUILD_DIR="${PKG_DIR}/build"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[node]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[node]${NC} $1"; }
log_error() { echo -e "${RED}[node]${NC} $1"; }

fetch() {
    if [ ! -f "${PKG_DIR}/node-v${NODE_VERSION}-linux-x64.tar.xz" ]; then
        log_info "Downloading Node.js ${NODE_VERSION}..."
        wget -q --show-progress "${NODE_URL}" -O "${PKG_DIR}/node-v${NODE_VERSION}-linux-x64.tar.xz"
    fi
    if [ ! -d "${BUILD_DIR}" ]; then
        log_info "Extracting Node.js..."
        mkdir -p "${BUILD_DIR}"
        tar -xf "${PKG_DIR}/node-v${NODE_VERSION}-linux-x64.tar.xz" -C "${BUILD_DIR}" --strip-components=1
    fi
}

pkg_install() {
    log_info "Installing Node.js to rootfs..."
    mkdir -p "${ROOTFS_DIR}/usr/local/bin" "${ROOTFS_DIR}/usr/local/lib"
    cp -a "${BUILD_DIR}/bin/"* "${ROOTFS_DIR}/usr/local/bin/"
    cp -a "${BUILD_DIR}/lib/"* "${ROOTFS_DIR}/usr/local/lib/"
    log_info "Node.js installed."
}

pack() {
    log_info "Packaging Node.js for WARP..."
    local pack_dir="${PKG_DIR}/pack_temp"
    rm -rf "${pack_dir}"
    mkdir -p "${pack_dir}/files"
    
    cp -a "${BUILD_DIR}/bin" "${pack_dir}/files/"
    cp -a "${BUILD_DIR}/lib" "${pack_dir}/files/"
    
    cat > "${pack_dir}/manifest.json" <<EOF
{
  "name": "node",
  "version": "${NODE_VERSION}",
  "install_bins": [
    "bin/node",
    "bin/npm",
    "bin/npx"
  ]
}
EOF

    local warp_file="node-${NODE_VERSION}-x86_64.warp"
    cd "${PKG_DIR}"
    if [ -f "/home/keytron46/git/WARP/warp" ]; then
        /home/keytron46/git/WARP/warp pack "${pack_dir}"
    else
        log_warn "WARP cli not found at /home/keytron46/git/WARP/warp, skipping packaging"
    fi
    rm -rf "${pack_dir}"
    
    if [ -f "${PKG_DIR}/${warp_file}" ]; then
        local sha=$(sha256sum "${PKG_DIR}/${warp_file}" | awk '{print $1}')
        local size=$(stat -c%s "${PKG_DIR}/${warp_file}")
        log_info "Package created: ${warp_file}"
        log_info "SHA256: ${sha}"
        log_info "Size: ${size} bytes"
    fi
}

case "${1:-all}" in
    fetch)   fetch ;;
    build)   fetch ;;
    install) fetch && pkg_install ;;
    pack)    fetch && pack ;;
    all)     fetch && pkg_install ;;
    clean)   rm -rf "${BUILD_DIR}" "${PKG_DIR}/pack_temp" ;;
    *) echo "Usage: $0 [fetch|build|install|pack|all|clean]"; exit 1 ;;
esac
