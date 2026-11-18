ARCHS = armv7
TARGET = iphone:clang:9.3:9.3
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ZeroGrav
ZeroGrav_FILES = Tweak.x
ZeroGrav_CFLAGS = -fobjc-arc
ZeroGrav_FRAMEWORKS = UIKit Foundation CoreMotion

include $(THEOS_MAKE_PATH)/tweak.mk
