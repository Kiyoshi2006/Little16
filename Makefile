# Little16 — iPhone X gestures for iOS 16
# Dopamine (rootless) — iOS 16.x — iPhone 8/8 Plus

export THEOS ?= $(HOME)/theos
export THEOS_PACKAGE_SCHEME = rootless

TARGET := iphone:clang:16.5:15.0
ARCHS = arm64

INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Little16

Little16_FILES = Tweak.xm
Little16_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable
Little16_FRAMEWORKS = UIKit Foundation

include $(THEOS)/makefiles/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard"
