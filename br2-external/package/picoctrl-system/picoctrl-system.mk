################################################################################
#
# picoctrl-system
#
################################################################################

PICOCTRL_SYSTEM_VERSION = local
PICOCTRL_SYSTEM_SITE = $(BR2_EXTERNAL_PICOOS_PATH)/../../picoctrl
PICOCTRL_SYSTEM_SITE_METHOD = local
PICOCTRL_SYSTEM_GOMOD = github.com/georgduees/picoctrl
PICOCTRL_SYSTEM_BUILD_TARGETS = ./cmd/picoctrl-system
PICOCTRL_SYSTEM_LICENSE = MIT, BSD-2-Clause, BSD-3-Clause
PICOCTRL_SYSTEM_LICENSE_FILES = \
	LICENSE \
	vendor/github.com/gorilla/websocket/LICENSE \
	vendor/google.golang.org/protobuf/LICENSE

define PICOCTRL_SYSTEM_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/bin/picoctrl-system \
		$(TARGET_DIR)/usr/sbin/picoctrl-system
endef

$(eval $(golang-package))

# All licenses for the currently vendored Go modules are listed above.
PICOCTRL_SYSTEM_LICENSE = MIT, BSD-2-Clause, BSD-3-Clause
