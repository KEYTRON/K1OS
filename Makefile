.PHONY: all clean help kernel rootfs iso packages busybox runit fish curl git dropbear modules warp

KERNEL_DIR  := $(CURDIR)/kernel/linux-6.19.10
CUSTOM_DIR  := $(CURDIR)/custom
BUILD_DIR   := $(CURDIR)/build
SCRIPTS_DIR := $(CURDIR)/scripts

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
	@echo "Build targets:"
	@echo "  make kernel     - Build Linux kernel"
	@echo "  make rootfs     - Build rootfs (BusyBox + runit + fish)"
	@echo "  make iso        - Build bootable ISO image"
	@echo "  make all-build  - Full build: kernel + rootfs + iso"
	@echo ""
	@echo "Package targets:"
	@echo "  make busybox    - Build BusyBox userland"
	@echo "  make runit      - Build runit init system"
	@echo "  make fish       - Build fish shell"
	@echo "  make tmux       - Build tmux terminal multiplexer"
	@echo "  make nano       - Build nano text editor"
	@echo "  make warp       - Build warp package manager"
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

# Kernel build
kernel:
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
rootfs: busybox runit fish curl git dropbear tmux nano python3 htop warp
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

# ISO image
iso:
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

# Test in QEMU
qemu:
	@if [ ! -f "$(CURDIR)/k1os.iso" ]; then \
		echo "ERROR: k1os.iso not found. Run: make iso"; \
		exit 1; \
	fi
	qemu-system-x86_64 -m 512M -cdrom $(CURDIR)/k1os.iso -vga virtio -enable-kvm

qemu-nographic:
	@if [ ! -f "$(CURDIR)/k1os.iso" ]; then \
		echo "ERROR: k1os.iso not found. Run: make iso"; \
		exit 1; \
	fi
	qemu-system-x86_64 -m 512M -cdrom $(CURDIR)/k1os.iso -nographic

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
	qemu-system-x86_64 -m 512M -cdrom $(CURDIR)/k1os.iso -hda $(CURDIR)/persist.qcow2 -vga virtio -enable-kvm

# Clean
clean:
	@echo "[clean] Cleaning build artifacts..."
	@$(MAKE) -C $(KERNEL_DIR) clean 2>/dev/null || true
	@rm -rf $(CURDIR)/packages/busybox/build \
	        $(CURDIR)/packages/runit/build \
	        $(CURDIR)/packages/fish/build \
	        $(CURDIR)/iso \
	        $(CURDIR)/k1os.iso
	@echo "[clean] Done"
