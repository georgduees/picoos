define PICOOS_INSTALL_KERNEL_LOGO
	cp "$(BR2_EXTERNAL_PICOOS_PATH)/board/zero2w/kernel-logo.ppm" \
		"$(@D)/drivers/video/logo/logo_linux_clut224.ppm"
endef

LINUX_PRE_CONFIGURE_HOOKS += PICOOS_INSTALL_KERNEL_LOGO

define PICOOS_INSTALL_BOOTANIM
	cp "$(BR2_EXTERNAL_PICOOS_PATH)/board/zero2w/psplash-bootanim.h" \
		"$(BR2_EXTERNAL_PICOOS_PATH)/board/zero2w/psplash-colors.h" "$(@D)/"
	sh "$(BR2_EXTERNAL_PICOOS_PATH)/../scripts/generate-bootanim.sh" \
		"$(BR2_EXTERNAL_PICOOS_PATH)/../bootanim.p8" > "$(@D)/picoos-bootanim-data.h"
endef

PSPLASH_PRE_CONFIGURE_HOOKS += PICOOS_INSTALL_BOOTANIM
