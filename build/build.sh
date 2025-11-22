#!/bin/bash

# K1OS Build Script
# This script handles the complete build process for K1OS

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
KERNEL_DIR="${SCRIPT_DIR}/kernel"
CUSTOM_DIR="${SCRIPT_DIR}/custom"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check for required tools
    local required_tools=("make" "gcc" "gcc")

    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "Required tool not found: $tool"
            exit 1
        fi
    done

    log_info "All prerequisites satisfied"
}

# Build kernel
build_kernel() {
    log_info "Building Linux kernel..."

    if [ ! -d "${KERNEL_DIR}/linux" ]; then
        log_error "Kernel source not found at ${KERNEL_DIR}/linux"
        log_warn "Please add kernel source first"
        exit 1
    fi

    cd "${KERNEL_DIR}/linux"
    make -j$(nproc)

    log_info "Kernel build completed"
}

# Build custom modules
build_custom() {
    log_info "Building custom modules..."

    if [ ! -d "${CUSTOM_DIR}/modules" ]; then
        log_warn "No custom modules directory found"
        return
    fi

    for module_dir in "${CUSTOM_DIR}/modules"/*/; do
        if [ -f "${module_dir}/Makefile" ]; then
            module_name=$(basename "${module_dir}")
            log_info "Building module: ${module_name}"
            make -C "${module_dir}"
        fi
    done

    log_info "Custom modules build completed"
}

# Main build function
main() {
    log_info "Starting K1OS build process..."

    check_prerequisites
    build_kernel
    build_custom

    log_info "Build completed successfully!"
}

# Show usage
usage() {
    echo "K1OS Build Script"
    echo ""
    echo "Usage: ./build/build.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --help              Show this help message"
    echo "  --check-only        Only check prerequisites"
    echo "  --kernel-only       Build only kernel"
    echo "  --custom-only       Build only custom code"
    echo ""
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --help)
            usage
            exit 0
            ;;
        --check-only)
            check_prerequisites
            exit 0
            ;;
        --kernel-only)
            check_prerequisites
            build_kernel
            exit 0
            ;;
        --custom-only)
            check_prerequisites
            build_custom
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
    shift
done

# Run main build
main
