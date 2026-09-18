.PHONY: all clean help kernel kernel-linux kernel-k1k k1k rootfs iso iso-linux iso-k1k disk test image packages busybox runit fish curl git dropbear modules warp wayland wlroots k1de rust go qemu qemu-linux qemu-k1k

export CFLAGS := -O2 -pipe -march=x86-64 -mtune=generic
export CXXFLAGS := $(CFLAGS)
export CPPFLAGS :=
export LDFLAGS :=

# Which kernel the boot media is built on: `k1k` (default — our own kernel,
# see KEYTRON/K1K) or `linux` (legacy Linux 7.0 profile).
KERNEL      ?= k1k
K1K_SOURCE_DIR ?=
export K1K_SOURCE_DIR

KERNEL_DIR  := $(CURDIR)/kernel/linux-7.0
CUSTOM_DIR  := $(CURDIR)/custom
BUILD_DIR   := $(CURDIR)/build
SCRIPTS_DIR := $(CURDIR)/scripts
K1K_OUT     := $(BUILD_DIR)/k1k
K1K_QEMU_DISK = -drive file=$(K1K_OUT)/k1os-k1k-disk.img,if=none,format=raw,id=nvme0 -device nvme,drive=nvme0,serial=K1OS-NVME-0001

# Default target
all: help

# Help target
help:
	@echo ""
	@echo "  ██╗  ██╗ ██╗ ██████╗ ███████╗"
	@echo "  ██║ ██╔╝███║██╔═══██╗██╔════╝"
	@echo "  █████╔╝ ╚██║██║   ██║███████╗"
	@echo "  ██╔═██╗  ██║██║   ██║╚════██║"
	@echo "  ██║  ██╗ ██║╚██████╔╝███████║"
	@echo "  ╚═╝  ╚═╝ ╚═╝ ╚═════╝ ╚══════╝"
	@echo "  Minimalist Developer OS"
	@echo ""
	@echo "Build targets (KERNEL=$(KERNEL); use KERNEL=linux for the legacy profile):"
	@echo "  make kernel     - Build the kernel (K1K from ../K1K or K1K_SOURCE_DIR)"
	@echo "  make iso        - Build bootable ISO image"
	@echo "  make disk       - Build the FAT16 service disk for the K1K profile"
	@echo "  make test       - Boot the K1K ISO headless in QEMU and check the log"
	@echo "  make rootfs     - Build Linux rootfs (BusyBox + runit + fish)"
	@echo "  make all-build  - Full build: kernel + rootfs + iso"
	@echo "  make image      - Build K1OS container image"
	@echo ""
	@echo "Package targets:"
	@echo "  make busybox    - Build BusyBox userland"
	@echo "  make runit      - Build runit init system"
	@echo "  make fish       - Build fish shell"
	@echo "  make tmux       - Build tmux terminal multiplexer"
	@echo "  make nano       - Build nano text editor"
	@echo "  make warp       - Build warp package manager from KEYTRON/WARP"
	@echo "  make k1de       - Build K1DE graphics environment (Rust + ASM)"
	@echo "  make rust       - Build/Install Rust compiler and Cargo"
	@echo "  make go         - Build/Install Go compiler and tools"
	@echo ""
	@echo "Desktop (K1DE libs):"
	@echo "  make wayland    - Build wayland + protocols"
	@echo "  make xkbcommon  - Build libxkbcommon"
	@echo "  make wlroots    - Build wlroots compositor library"
	@echo ""
	@echo "Custom code:"
	@echo "  make modules    - Build custom kernel modules"
	@echo ""
	@echo "Utilities:"
	@echo "  make clean        - Clean all build artifacts"
	@echo "  make qemu         - Test in QEMU (RAM mode)"
	@echo "  make make-persist - Create persist.qcow2 for QEMU"
	@echo "  make qemu-persist - Test in QEMU with persistent storage"
	@echo ""

# Full build
all-build: kernel rootfs iso

# Kernel / ISO / QEMU dispatch on KERNEL.
ifeq ($(KERNEL),k1k)
kernel: kernel-k1k
iso: iso-k1k
qemu: qemu-k1k
else
kernel: kernel-linux
iso: iso-linux
qemu: qemu-linux
endif

# K1K profile: everything goes through scripts/build-k1k.sh into build/k1k/.
kernel-k1k k1k:
	@bash $(SCRIPTS_DIR)/build-k1k.sh kernel

iso-k1k:
	@bash $(SCRIPTS_DIR)/build-k1k.sh iso

disk:
	@bash $(SCRIPTS_DIR)/build-k1k.sh disk

test:
	@bash $(SCRIPTS_DIR)/build-k1k.sh test

qemu-k1k:
	@test -f $(K1K_OUT)/k1os-k1k.iso || $(MAKE) iso-k1k
	@test -f $(K1K_OUT)/k1os-k1k-disk.img || $(MAKE) disk
	qemu-system-x86_64 -M q35 -m 512M -smp 4 -enable-kvm -cpu host \
		-cdrom $(K1K_OUT)/k1os-k1k.iso -boot d -serial stdio $(K1K_QEMU_DISK)

# Linux kernel build (legacy profile)
kernel-linux:
	@echo "[kernel] Configuring and building Linux kernel..."
	@if [ ! -d "$(KERNEL_DIR)" ]; then \
		echo "ERROR: Kernel source not found at $(KERNEL_DIR)"; \
		exit 1; \
	fi
	@if [ ! -f "$(KERNEL_DIR)/.config" ]; then \
		echo "[kernel] No .config found, using K1OS default config..."; \
		cp $(BUILD_DIR)/kernel.config $(KERNEL_DIR)/.config; \
		$(MAKE) -C $(KERNEL_DIR) olddefconfig; \
	fi
	$(MAKE) -C $(KERNEL_DIR) -j$(shell nproc)
	@echo "[kernel] Build complete: $(KERNEL_DIR)/arch/x86/boot/bzImage"

# Rootfs build (all components)
rootfs: busybox runit fish curl git dropbear tmux nano python3 htop warp rust go node tailscale
	@bash $(SCRIPTS_DIR)/build-rootfs.sh

# Individual packages
busybox:
	@bash $(CURDIR)/packages/busybox/build.sh all

runit:
	@bash $(CURDIR)/packages/runit/build.sh all

fish:
	@bash $(CURDIR)/packages/fish/build.sh all

curl:
	@bash $(CURDIR)/packages/curl/build.sh all

git:
	@bash $(CURDIR)/packages/git/build.sh all

dropbear:
	@bash $(CURDIR)/packages/dropbear/build.sh all

tmux:
	@bash $(CURDIR)/packages/tmux/build.sh all

nano:
	@bash $(CURDIR)/packages/nano/build.sh all

python3:
	@bash $(CURDIR)/packages/python3/build.sh all

htop:
	@bash $(CURDIR)/packages/htop/build.sh all

warp:
	@bash $(CURDIR)/packages/warp/build.sh all

# Desktop Environment (K1DE)
wayland:
	@bash $(CURDIR)/packages/wayland/build.sh all
	@bash $(CURDIR)/packages/wl-protocols/build.sh all

xkbcommon:
	@bash $(CURDIR)/packages/libxkbcommon/build.sh all

wlroots: wayland xkbcommon
	@bash $(CURDIR)/packages/wlroots/build.sh all

#k1de:
#	@bash $(CURDIR)/packages/k1de/build.sh all

rust:
	@bash $(CURDIR)/packages/rust/build.sh all

go:
	@bash $(CURDIR)/packages/go/build.sh all

node:
	@bash $(CURDIR)/packages/node/build.sh all

tailscale:
	@bash $(CURDIR)/packages/tailscale/build.sh all



# Container image
image: rootfs
	@docker build -t k1os:local -f $(CURDIR)/Dockerfile $(CURDIR)

# ISO image (legacy Linux profile: GRUB + vmlinuz + initramfs + squashfs)
iso-linux:
	@bash $(SCRIPTS_DIR)/build-iso.sh

# Custom kernel modules
modules:
	@echo "[modules] Building custom kernel modules..."
	@for module in $(CUSTOM_DIR)/modules/*/; do \
		if [ -f "$$module/Makefile" ]; then \
			echo "[modules] Building $$(basename $$module)..."; \
			$(MAKE) -C "$$module" KERNEL_SRC=$(KERNEL_DIR); \
		fi; \
	done

# Test the Linux profile in QEMU
qemu-linux:
	@if [ ! -f "$(CURDIR)/k1os.iso" ]; then \
		echo "ERROR: k1os.iso not found. Run: make iso"; \
		exit 1; \
	fi
	qemu-system-x86_64 -m 512M -cdrom $(CURDIR)/k1os.iso -vga virtio -enable-kvm -cpu host,+avx,+avx2

qemu-nographic:
	@if [ ! -f "$(CURDIR)/k1os.iso" ]; then \
		echo "ERROR: k1os.iso not found. Run: make iso"; \
		exit 1; \
	fi
	qemu-system-x86_64 -m 512M -cdrom $(CURDIR)/k1os.iso -nographic -enable-kvm -cpu host,+avx,+avx2

# Persistent storage: создать qcow2 + запустить QEMU с ним
make-persist:
	@bash $(SCRIPTS_DIR)/make-persist.sh $(CURDIR)/persist.qcow2 2048

qemu-persist:
	@if [ ! -f "$(CURDIR)/k1os.iso" ]; then \
		echo "ERROR: k1os.iso not found. Run: make iso"; \
		exit 1; \
	fi
	@if [ ! -f "$(CURDIR)/persist.qcow2" ]; then \
		echo "No persist.qcow2 found. Run: make make-persist"; \
		exit 1; \
	fi
	qemu-system-x86_64 -m 512M -cdrom $(CURDIR)/k1os.iso -hda $(CURDIR)/persist.qcow2 -vga virtio -enable-kvm -cpu host,+avx,+avx2

# Clean
clean:
	@echo "[clean] Cleaning build artifacts..."
	@$(MAKE) -C $(KERNEL_DIR) clean 2>/dev/null || true
	@rm -rf $(CURDIR)/packages/busybox/build \
	        $(CURDIR)/packages/runit/build \
	        $(CURDIR)/packages/fish/build \
	        $(CURDIR)/packages/k1de/target \
	        $(CURDIR)/packages/rust/build \
	        $(CURDIR)/packages/go/build \
	        $(CURDIR)/iso \
	        $(CURDIR)/k1os.iso
	@echo "[clean] Done"
