.PHONY: all clean help kernel custom modules build install

KERNEL_DIR := $(CURDIR)/kernel
CUSTOM_DIR := $(CURDIR)/custom
BUILD_DIR := $(CURDIR)/build
SCRIPTS_DIR := $(CURDIR)/scripts

# Default target
all: help

# Help target
help:
	@echo "K1OS - Linux Kernel Migration Project"
	@echo ""
	@echo "Available targets:"
	@echo "  make kernel      - Build Linux kernel"
	@echo "  make custom      - Build custom modules and tools"
	@echo "  make modules     - Build custom kernel modules"
	@echo "  make build       - Full build (kernel + custom)"
	@echo "  make clean       - Clean build artifacts"
	@echo "  make help        - Show this help message"
	@echo ""

# Kernel build
kernel:
	@echo "Building Linux kernel..."
	@if [ -d "$(KERNEL_DIR)/linux" ]; then \
		$(MAKE) -C $(KERNEL_DIR)/linux; \
	else \
		echo "Kernel source not found in $(KERNEL_DIR)/linux"; \
		exit 1; \
	fi

# Custom modules build
modules:
	@echo "Building custom modules..."
	@if [ -d "$(CUSTOM_DIR)/modules" ]; then \
		for module in $(CUSTOM_DIR)/modules/*/; do \
			if [ -f "$$module/Makefile" ]; then \
				echo "Building $$(basename $$module)..."; \
				$(MAKE) -C "$$module"; \
			fi; \
		done; \
	fi

# Custom code build
custom: modules
	@echo "Building custom code..."
	@if [ -d "$(CUSTOM_DIR)/tools" ]; then \
		for tool in $(CUSTOM_DIR)/tools/*/; do \
			if [ -f "$$tool/Makefile" ]; then \
				echo "Building $$(basename $$tool)..."; \
				$(MAKE) -C "$$tool"; \
			fi; \
		done; \
	fi

# Full build
build: kernel custom
	@echo "Full build completed"

# Clean
clean:
	@echo "Cleaning build artifacts..."
	@if [ -d "$(KERNEL_DIR)/linux" ]; then \
		$(MAKE) -C $(KERNEL_DIR)/linux clean; \
	fi
	@for dir in $(CUSTOM_DIR)/modules/* $(CUSTOM_DIR)/tools/*; do \
		if [ -f "$$dir/Makefile" ]; then \
			$(MAKE) -C "$$dir" clean; \
		fi; \
	done
	@echo "Clean completed"
