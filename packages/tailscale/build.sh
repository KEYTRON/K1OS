#!/bin/bash
# Build/Install Tailscale for K1OS

set -e

TAILSCALE_VERSION="1.68.1"
TAILSCALE_URL="https://pkgs.tailscale.com/stable/tailscale_${TAILSCALE_VERSION}_amd64.tgz"
PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${PKG_DIR}/../.." && pwd)"
ROOTFS_DIR="${ROOT_DIR}/rootfs"
BUILD_DIR="${PKG_DIR}/build"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[tailscale]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[tailscale]${NC} $1"; }
log_error() { echo -e "${RED}[tailscale]${NC} $1"; }

fetch() {
    if [ ! -f "${PKG_DIR}/tailscale_${TAILSCALE_VERSION}_amd64.tgz" ]; then
        log_info "Downloading Tailscale ${TAILSCALE_VERSION}..."
        wget -q --show-progress "${TAILSCALE_URL}" -O "${PKG_DIR}/tailscale_${TAILSCALE_VERSION}_amd64.tgz"
    fi
    if [ ! -d "${BUILD_DIR}" ]; then
        log_info "Extracting Tailscale..."
        mkdir -p "${BUILD_DIR}"
        tar -xzf "${PKG_DIR}/tailscale_${TAILSCALE_VERSION}_amd64.tgz" -C "${BUILD_DIR}" --strip-components=1
    fi
}

pkg_install() {
    log_info "Installing Tailscale to rootfs..."
    mkdir -p "${ROOTFS_DIR}/usr/local/bin" "${ROOTFS_DIR}/etc/sv/tailscaled"
    cp "${BUILD_DIR}/tailscale" "${ROOTFS_DIR}/usr/local/bin/"
    cp "${BUILD_DIR}/tailscaled" "${ROOTFS_DIR}/usr/local/bin/"
    
    cat > "${ROOTFS_DIR}/etc/sv/tailscaled/run" <<EOF
#!/bin/sh
exec /usr/local/bin/tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/var/run/tailscale/tailscaled.sock
EOF
    chmod +x "${ROOTFS_DIR}/etc/sv/tailscaled/run"
    
    mkdir -p "${ROOTFS_DIR}/var/service" "${ROOTFS_DIR}/var/lib/tailscale" "${ROOTFS_DIR}/var/run/tailscale"
    ln -sf /etc/sv/tailscaled "${ROOTFS_DIR}/var/service/tailscaled" 2>/dev/null || true

    log_info "Tailscale installed."
}

pack() {
    log_info "Packaging Tailscale for WARP..."
    local pack_dir="${PKG_DIR}/pack_temp"
    rm -rf "${pack_dir}"
    mkdir -p "${pack_dir}/files/bin" "${pack_dir}/files/etc/sv/tailscaled" "${pack_dir}/files/var/lib/tailscale" "${pack_dir}/files/var/run/tailscale"
    
    cp "${BUILD_DIR}/tailscale" "${pack_dir}/files/bin/"
    cp "${BUILD_DIR}/tailscaled" "${pack_dir}/files/bin/"
    
    cat > "${pack_dir}/files/etc/sv/tailscaled/run" <<EOF
#!/bin/sh
exec /usr/local/bin/tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/var/run/tailscale/tailscaled.sock
EOF
    chmod +x "${pack_dir}/files/etc/sv/tailscaled/run"
    
    cat > "${pack_dir}/manifest.json" <<EOF
{
  "name": "tailscale",
  "version": "${TAILSCALE_VERSION}",
  "install_bins": [
    "bin/tailscale",
    "bin/tailscaled"
  ]
}
EOF

    local warp_file="tailscale-${TAILSCALE_VERSION}-x86_64.warp"
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
