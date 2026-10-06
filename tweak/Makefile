TARGET := iphone:clang:latest:16.0
ARCHS := arm64
FINALPACKAGE := 1

# version.txt at the repo root is the one version. Theos stamps PACKAGE_VERSION into the .deb (control has
# no Version line) and reads it while common.mk loads, so it is set above the include.
PG_VERSION := $(or $(shell cat ../version.txt 2>/dev/null),0.0.0)
PACKAGE_VERSION := $(PG_VERSION)

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := pureglass

# Every source under Sources/, so a new file needs no Makefile edit.
# SGFlagList.m is written by scripts/extract-flags.py for a flags page that no longer exists, and it imports a
# header that is gone, so it is left out.
pureglass_FILES := $(filter-out Sources/Shared/Flags/SGFlagList.m,$(shell find Sources -name '*.m' -o -name '*.x' | sort))
pureglass_CFLAGS := -fobjc-arc -ISources -DPG_VERSION=\"$(PG_VERSION)\"
pureglass_FRAMEWORKS := UIKit QuartzCore CoreImage CoreText
# Runtime swizzling instead of Substrate so the dylib has no extra dependency inside the IPA.
pureglass_LOGOS_DEFAULT_GENERATOR := internal

include $(THEOS_MAKE_PATH)/tweak.mk
