TARGET =: clang::5.0
ARCHS = armv7 armv7s arm64 arm64e
DEBUG = 0

PACKAGE_VERSION = $(THEOS_PACKAGE_BASE_VERSION)
THEOS_PACKAGE_DIR_NAME = debs

include $(THEOS)/makefiles/common.mk

TOOL_NAME = myinst
myinst_FILES = myinst.m $(wildcard zipzap/*.c) $(wildcard zipzap/*.cpp) $(wildcard zipzap/*.m) $(wildcard zipzap/*.mm)
myinst_CCFLAGS += -std=c++11 -stdlib=libc++ -fobjc-arc -include ./zipzap/zipzap-Prefix.pch -I./zipzap -fvisibility=hidden -Wno-unused-property-ivar
myinst_CFLAGS += -fobjc-arc -include ./zipzap/zipzap-Prefix.pch -I./zipzap -fvisibility=hidden -Wno-unused-property-ivar
myinst_FRAMEWORKS = Foundation ImageIO CoreGraphics
myinst_PRIVATE_FRAMEWORKS = MobileCoreServices
myinst_LIBRARIES = z
myinst_INSTALL_PATH = /usr/bin
myinst_CODESIGN_FLAGS = -Smyinst_entitlements.plist
include $(THEOS_MAKE_PATH)/tool.mk
