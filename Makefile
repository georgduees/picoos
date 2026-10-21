BUILDROOT_DIR := $(CURDIR)/buildroot
OUTPUT_DIR := $(CURDIR)/output
EXTERNAL_DIR := $(CURDIR)/br2-external
DEFCONFIG := picoos_zero2w_defconfig

.PHONY: configure build clean

configure:
	$(MAKE) -C $(BUILDROOT_DIR) O=$(OUTPUT_DIR) BR2_EXTERNAL=$(EXTERNAL_DIR) $(DEFCONFIG)

build:
	$(MAKE) -C $(BUILDROOT_DIR) O=$(OUTPUT_DIR) BR2_EXTERNAL=$(EXTERNAL_DIR)

clean:
	$(MAKE) -C $(BUILDROOT_DIR) O=$(OUTPUT_DIR) clean
