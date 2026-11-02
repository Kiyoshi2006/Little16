# Little16 — iPhone X gestures for iOS 16
# Dopamine (rootless) — iOS 16.x — iPhone 8/8 Plus

# ── Theos path ──────────────────────────────────────────────────────────────
# Dopamine theos thường nằm ở ~/theos hoặc /var/jb/var/theos
# Nếu build trên máy Mac thì export THEOS=~/theos trước khi chạy make
export THEOS ?= $(HOME)/theos

# ── Rootless (Dopamine) ─────────────────────────────────────────────────────
export THEOS_PACKAGE_SCHEME = rootless

# ── Respring target process ─────────────────────────────────────────────────
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

# ── Tweak ────────────────────────────────────────────────────────────────────
TWEAK_NAME = Little16

Little16_FILES          = Tweak.xm
Little16_CFLAGS         = -fobjc-arc -Wall -Wno-unused-variable
Little16_FRAMEWORKS     = UIKit CoreFoundation Foundation
Little16_PRIVATE_FRAMEWORKS = SpringBoardUI SpringBoardFoundation SpringBoard

# iOS 16 minimum deployment target
Little16_DEPLOYMENT_TARGET = 16.0

include $(THEOS)/makefiles/tweak.mk

# ── Helpers ───────────────────────────────────────────────────────────────────
after-install::
	install.exec "killall -9 SpringBoard"
