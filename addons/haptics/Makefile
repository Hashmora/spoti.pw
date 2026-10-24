# Vitrine Haptics: Music Haptics > Everywhere's SpringBoard side, a rootless package of its own (HapticRelay.x).
# Build from here: env -u MAKELEVEL gmake package. Vitrine's own tweak/ does not build or carry it.
TARGET := iphone:clang:latest:16.0
ARCHS := arm64 arm64e
FINALPACKAGE := 1
THEOS_PACKAGE_SCHEME ?= rootless
PACKAGE_VERSION := $(or $(shell cat ../../version.txt 2>/dev/null | tr - '~'),0.0.0)

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := VitrineHaptics
VitrineHaptics_FILES := HapticRelay.x
VitrineHaptics_CFLAGS := -fobjc-arc
VitrineHaptics_FRAMEWORKS := UIKit CoreHaptics
VitrineHaptics_LOGOS_DEFAULT_GENERATOR := internal

include $(THEOS_MAKE_PATH)/tweak.mk
