BUILDROOT_DIR := $(CURDIR)/buildroot
OUTPUT_DIR := $(CURDIR)/output
EXTERNAL_DIR := $(CURDIR)/br2-external
DEFCONFIG := picoos_zero2w_defconfig

.PHONY: bootstrap configure build clean

bootstrap:
	./scripts/bootstrap-buildroot.sh

configure: bootstrap
	$(MAKE) -C $(BUILDROOT_DIR) O=$(OUTPUT_DIR) BR2_EXTERNAL=$(EXTERNAL_DIR) $(DEFCONFIG)

build: bootstrap
	@test -f $(OUTPUT_DIR)/.config || { echo "Run 'make configure' first." >&2; exit 1; }
	$(MAKE) -C $(BUILDROOT_DIR) O=$(OUTPUT_DIR) BR2_EXTERNAL=$(EXTERNAL_DIR)

clean:
	$(MAKE) -C $(BUILDROOT_DIR) O=$(OUTPUT_DIR) clean
