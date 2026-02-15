#!/bin/bash
# Build tmux for K1OS

set -e

TMUX_VERSION="3.5a"
TMUX_URL="https://github.com/tmux/tmux/releases/download/${TMUX_VERSION}/tmux-${TMUX_VERSION}.tar.gz"
PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${PKG_DIR}/../.." && pwd)"
ROOTFS_DIR="${ROOT_DIR}/rootfs"
BUILD_DIR="${PKG_DIR}/build"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[tmux]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[tmux]${NC} $1"; }
log_error() { echo -e "${RED}[tmux]${NC} $1"; }

check_deps() {
    for dep in gcc make pkg-config; do
        command -v "$dep" &>/dev/null || { log_error "Missing: $dep"; exit 1; }
    done
    pkg-config --exists libevent ncurses 2>/dev/null || {
        log_warn "Install: sudo dnf install libevent-devel ncurses-devel"
        exit 1
    }
}

fetch() {
    if [ ! -f "${PKG_DIR}/tmux-${TMUX_VERSION}.tar.gz" ]; then
        log_info "Downloading tmux ${TMUX_VERSION}..."
        wget -q --show-progress "${TMUX_URL}" -O "${PKG_DIR}/tmux-${TMUX_VERSION}.tar.gz"
    fi
    if [ ! -d "${BUILD_DIR}" ]; then
        log_info "Extracting tmux..."
        mkdir -p "${BUILD_DIR}"
        tar -xzf "${PKG_DIR}/tmux-${TMUX_VERSION}.tar.gz" -C "${BUILD_DIR}" --strip-components=1
    fi
}

build() {
    log_info "Configuring tmux..."
    cd "${BUILD_DIR}"
    ./configure \
        --prefix=/usr \
        --silent

    log_info "Building tmux..."
    make -j$(nproc) --silent
}

pkg_install() {
    log_info "Installing tmux to rootfs..."
    make -C "${BUILD_DIR}" install DESTDIR="${ROOTFS_DIR}" --silent

    # Копируем зависимые библиотеки
    for lib in $(ldd "${ROOTFS_DIR}/usr/bin/tmux" 2>/dev/null | grep "=>" | awk '{print $3}' | grep -v "^$"); do
        [ -f "$lib" ] && cp -n "$lib" "${ROOTFS_DIR}/lib64/" 2>/dev/null || true
    done

    # Базовый tmux.conf
    cat > "${ROOTFS_DIR}/etc/tmux.conf" << 'EOF'
# K1OS tmux config
set -g default-terminal "xterm-256color"
set -g history-limit 10000
set -g mouse on

# Prefix: Ctrl+a (like screen)
unbind C-b
set -g prefix C-a
bind C-a send-prefix

# Split panes
bind | split-window -h
bind - split-window -v

# Status bar
set -g status-style bg=black,fg=white
set -g status-left "#[fg=green][K1OS] "
set -g status-right "#[fg=yellow]%H:%M"
EOF

    log_info "tmux installed: $(${ROOTFS_DIR}/usr/bin/tmux -V 2>/dev/null || echo 'OK')"
}

case "${1:-all}" in
    fetch)   fetch ;;
    build)   check_deps && fetch && build ;;
    install) check_deps && fetch && build && pkg_install ;;
    all)     check_deps && fetch && build && pkg_install ;;
    clean)   rm -rf "${BUILD_DIR}" ;;
    *) echo "Usage: $0 [fetch|build|install|all|clean]"; exit 1 ;;
esac
