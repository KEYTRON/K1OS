#!/bin/bash
# Build BusyBox for K1OS userland
# BusyBox provides ~400 Unix utilities in a single binary

set -e

BUSYBOX_VERSION="1.37.0"
BUSYBOX_URL="https://busybox.net/downloads/busybox-${BUSYBOX_VERSION}.tar.bz2"
PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${PKG_DIR}/../.." && pwd)"
ROOTFS_DIR="${ROOT_DIR}/rootfs"
BUILD_DIR="${PKG_DIR}/build"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[busybox]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[busybox]${NC} $1"; }
log_error() { echo -e "${RED}[busybox]${NC} $1"; }

fetch() {
    if [ ! -f "${PKG_DIR}/busybox-${BUSYBOX_VERSION}.tar.bz2" ]; then
        log_info "Downloading BusyBox ${BUSYBOX_VERSION}..."
        wget -q --show-progress "${BUSYBOX_URL}" -O "${PKG_DIR}/busybox-${BUSYBOX_VERSION}.tar.bz2"
    else
        log_info "BusyBox source already downloaded"
    fi

    if [ ! -d "${BUILD_DIR}" ]; then
        log_info "Extracting BusyBox..."
        mkdir -p "${BUILD_DIR}"
        tar -xjf "${PKG_DIR}/busybox-${BUSYBOX_VERSION}.tar.bz2" -C "${BUILD_DIR}" --strip-components=1
    fi
}

apply_patches() {
    if grep -q 'static void cpuid(unsigned \*eax, unsigned \*ebx, unsigned \*ecx, unsigned \*edx)' "${BUILD_DIR}/libbb/hash_md5_sha.c"; then
        log_info "Applying BusyBox SHA hwaccel backport for GitHub runner compatibility..."
        patch -d "${BUILD_DIR}" -p1 <<'EOF'
--- a/libbb/hash_md5_sha.c
+++ b/libbb/hash_md5_sha.c
@@ -15,18 +15,28 @@
 
 #if ENABLE_SHA1_HWACCEL || ENABLE_SHA256_HWACCEL
 # if defined(__GNUC__) && (defined(__i386__) || defined(__x86_64__))
-static void cpuid(unsigned *eax, unsigned *ebx, unsigned *ecx, unsigned *edx)
+static void cpuid_eax_ebx_ecx(unsigned *eax, unsigned *ebx, unsigned *ecx, unsigned *edx)
 {
 	asm ("cpuid"
 		: "=a"(*eax), "=b"(*ebx), "=c"(*ecx), "=d"(*edx)
-		: "0"(*eax),  "1"(*ebx),  "2"(*ecx),  "3"(*edx)
+		: "0" (*eax), "1" (*ebx), "2" (*ecx)
 	);
 }
 static smallint shaNI;
-static int get_shaNI(void)
+static NOINLINE int get_shaNI(void)
 {
-	unsigned eax = 7, ebx = ebx, ecx = 0, edx = edx;
-	cpuid(&eax, &ebx, &ecx, &edx);
+	/* Get leaf 7 subleaf 0. Exists on all CPUs since Merom (2006).
+	 * "If a value entered for CPUID.EAX is higher than the maximum
+	 * input value for basic or extended function for that processor
+	 * then the data for the highest basic information leaf is returned".
+	 * This means that Pentiums 4 would return leaf 5 or 6 instead of 7,
+	 * which happen to have zero in EBX bit 29. Thus they should work too.
+	 */
+	unsigned eax = 7;
+	unsigned ecx = 0;
+	unsigned ebx = 0; /* should not be needed, paranoia */
+	unsigned edx;
+	cpuid_eax_ebx_ecx(&eax, &ebx, &ecx, &edx);
 	ebx = ((ebx >> 28) & 2) - 1; /* bit 29 -> 1 or -1 */
 	shaNI = (int)ebx;
 	return (int)ebx;
@@ -1300,7 +1310,14 @@ unsigned FAST_FUNC sha1_end(sha1_ctx_t *ctx, void *resbuf)
 	/* SHA stores total in BE, need to swap on LE arches: */
 	common64_end(ctx, /*swap_needed:*/ BB_LITTLE_ENDIAN);
 
-	hash_size = (ctx->process_block == sha1_process_block64) ? 5 : 8;
+	hash_size = 8;
+	if (ctx->process_block == sha1_process_block64
+#if ENABLE_SHA1_HWACCEL
+	 || ctx->process_block == sha1_process_block64_shaNI
+#endif
+	) {
+		hash_size = 5;
+	}
 	/* This way we do not impose alignment constraints on resbuf: */
 	if (BB_LITTLE_ENDIAN) {
 		unsigned i;
EOF
    fi
}

build() {
    apply_patches

    log_info "Configuring BusyBox (static build)..."
    make -C "${BUILD_DIR}" defconfig
    # Force x86-64 baseline (no AVX/SSE4) for QEMU compatibility
    sed -i 's/CONFIG_EXTRA_CFLAGS=""/CONFIG_EXTRA_CFLAGS="-march=x86-64 -mtune=generic -mno-avx -mno-avx2 -mno-avx512f -mno-sse4.2 -mno-sse4.1"/' "${BUILD_DIR}/.config"
    # Enable static linking (no external libc dependency)
    sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' "${BUILD_DIR}/.config"
    sed -i 's/CONFIG_STATIC=n/CONFIG_STATIC=y/' "${BUILD_DIR}/.config"
    # Disable tc applet (uses CBQ structs removed from newer kernel headers)
    sed -i 's/CONFIG_TC=y/# CONFIG_TC is not set/' "${BUILD_DIR}/.config"

    log_info "Building BusyBox..."
    make -C "${BUILD_DIR}" -j"$(nproc)"
}

pkg_install() {
    log_info "Installing BusyBox to rootfs..."
    make -C "${BUILD_DIR}" install CONFIG_PREFIX="${ROOTFS_DIR}"
    log_info "BusyBox installed to ${ROOTFS_DIR}"
}

case "${1:-all}" in
    fetch)   fetch ;;
    build)   fetch && build ;;
    install) fetch && build && pkg_install ;;
    all)     fetch && build && pkg_install ;;
    clean)
        log_info "Cleaning BusyBox build..."
        rm -rf "${BUILD_DIR}"
        ;;
    *)
        echo "Usage: $0 [fetch|build|install|all|clean]"
        exit 1
        ;;
esac
