define PICOOS_INSTALL_KERNEL_LOGO
	cp "$(BR2_EXTERNAL_PICOOS_PATH)/board/zero2w/kernel-logo.ppm" \
		"$(@D)/drivers/video/logo/logo_linux_clut224.ppm"
endef

LINUX_PRE_CONFIGURE_HOOKS += PICOOS_INSTALL_KERNEL_LOGO
