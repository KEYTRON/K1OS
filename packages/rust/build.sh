#!/bin/bash
# Build/Install Rust for K1OS

set -e

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[rust]${NC} $1"; }

case "${1:-all}" in
    fetch)   log_info "Rust is available via warp (warp install rust)" ;;
    build)   log_info "Rust is available via warp (warp install rust)" ;;
    install) log_info "Rust is available via warp (warp install rust)" ;;
    pack)    log_info "Rust is available via warp (warp install rust)" ;;
    all)     log_info "Rust is available via warp (warp install rust)" ;;
    clean)   ;;
    *) echo "Usage: $0 [fetch|build|install|pack|all|clean]"; exit 1 ;;
esac
