export THEOS ?= $(HOME)/theos
export THEOS_PACKAGE_SCHEME = rootless

TARGET := iphone:clang:16.5:15.0
ARCHS = arm64

INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Little16CC

Little16CC_FILES = Tweak.xm
Little16CC_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable
Little16CC_FRAMEWORKS = UIKit Foundation

include $(THEOS)/makefiles/tweak.mk
