.PHONY: all clean help kernel rootfs iso packages busybox runit fish modules

KERNEL_DIR  := $(CURDIR)/kernel/linux-6.17.9
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
	@echo ""
	@echo "Custom code:"
	@echo "  make modules    - Build custom kernel modules"
	@echo ""
	@echo "Utilities:"
	@echo "  make clean      - Clean all build artifacts"
	@echo "  make qemu       - Test in QEMU (requires k1os.iso)"
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
rootfs: busybox runit fish
	@bash $(SCRIPTS_DIR)/build-rootfs.sh

# Individual packages
busybox:
	@bash $(CURDIR)/packages/busybox/build.sh all

runit:
	@bash $(CURDIR)/packages/runit/build.sh all

fish:
	@bash $(CURDIR)/packages/fish/build.sh all

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
