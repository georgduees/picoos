BUILDROOT_DIR := $(CURDIR)/buildroot
OUTPUT_DIR ?= $(CURDIR)/output
DOWNLOAD_DIR ?= $(CURDIR)/dl
CCACHE_DIR ?= $(OUTPUT_DIR)/ccache
EXTERNAL_DIR := $(CURDIR)/br2-external
DEFCONFIG := picoos_zero2w_defconfig

.PHONY: bootstrap configure build clean

bootstrap:
	./scripts/bootstrap-buildroot.sh

configure: bootstrap
	BR2_CCACHE_DIR="$(CCACHE_DIR)" $(MAKE) -C $(BUILDROOT_DIR) O=$(OUTPUT_DIR) BR2_EXTERNAL=$(EXTERNAL_DIR) BR2_DL_DIR=$(DOWNLOAD_DIR) $(DEFCONFIG)

build: bootstrap
	@test -f $(OUTPUT_DIR)/.config || { echo "Run 'make configure' first." >&2; exit 1; }
	BR2_CCACHE_DIR="$(CCACHE_DIR)" $(MAKE) -C $(BUILDROOT_DIR) O=$(OUTPUT_DIR) BR2_EXTERNAL=$(EXTERNAL_DIR) BR2_DL_DIR=$(DOWNLOAD_DIR)

clean:
	BR2_CCACHE_DIR="$(CCACHE_DIR)" $(MAKE) -C $(BUILDROOT_DIR) O=$(OUTPUT_DIR) BR2_DL_DIR=$(DOWNLOAD_DIR) clean
