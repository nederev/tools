PREFIX ?= $(HOME)/.hammerspoon
BINDIR ?= $(PREFIX)/bin
MODULEDIR ?= $(PREFIX)
BUILD_DIR ?= build
APPDIR ?= $(HOME)/Applications
APP_NAME := Sidecar Reconnector
APP_VERSION := $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" app/Info.plist 2>/dev/null || echo dev)
APP_BUNDLE_PATH := $(BUILD_DIR)/$(APP_NAME).app
INSTALLED_APP := $(APPDIR)/$(APP_NAME).app
DMG_STAGING := $(BUILD_DIR)/dmg
DMG := $(BUILD_DIR)/Sidecar-Reconnector-v$(APP_VERSION).dmg

CC ?= clang
CFLAGS ?= -fobjc-arc -fblocks -Wall -Wextra -Wpedantic
CLI_FRAMEWORKS := -framework Foundation
APP_FRAMEWORKS := -framework Foundation -framework AppKit -framework Carbon

BIN := $(BUILD_DIR)/sidecarctl
TEST_BIN := $(BUILD_DIR)/sidecar-tests
APP_BUNDLE := $(BUILD_DIR)/Sidecar\ Reconnector.app
APP_CONTENTS := $(APP_BUNDLE)/Contents
APP_MACOS := $(APP_CONTENTS)/MacOS
APP_RESOURCES := $(APP_CONTENTS)/Resources
APP_BIN := $(APP_MACOS)/SidecarReconnector
APP_INFO := $(APP_CONTENTS)/Info.plist
APP_ICON := $(APP_RESOURCES)/SidecarReconnector.icns
CORE_SRC := src/SidecarController.m
CLI_SRC := src/sidecarctl.m
APP_SRC := src/SidecarReconnectorApp.m
TEST_SRC := tests/resolve_tests.m
VERSION ?=
BUILD ?=

.PHONY: all clean install install-app install-app-health launch-app install-hammerspoon reload test unit-test smoke bump-version bump-build release-build dmg app-health

all: $(BIN) $(APP_BUNDLE)

$(BIN): $(CLI_SRC) $(CORE_SRC) src/SidecarController.h
	mkdir -p $(BUILD_DIR)
	$(CC) $(CFLAGS) $(CLI_FRAMEWORKS) $(CLI_SRC) $(CORE_SRC) -o $(BIN)

$(TEST_BIN): $(TEST_SRC) $(CORE_SRC) src/SidecarController.h
	mkdir -p $(BUILD_DIR)
	$(CC) $(CFLAGS) $(CLI_FRAMEWORKS) -Isrc $(TEST_SRC) $(CORE_SRC) -o $(TEST_BIN)

$(APP_BUNDLE): $(APP_BIN) $(APP_INFO) $(APP_ICON)

$(APP_BIN): $(APP_SRC) $(CORE_SRC) src/SidecarController.h
	mkdir -p $(APP_MACOS)
	$(CC) $(CFLAGS) $(APP_FRAMEWORKS) $(APP_SRC) $(CORE_SRC) -o $(APP_BIN)

$(APP_INFO): app/Info.plist
	mkdir -p $(APP_CONTENTS)
	cp app/Info.plist $(APP_INFO)

$(APP_ICON): app/Resources/SidecarReconnector.icns app/Resources/SidecarReconnectorIcon.png
	mkdir -p $(APP_RESOURCES)
	cp -R app/Resources/. $(APP_RESOURCES)/

install: all install-hammerspoon
	mkdir -p $(BINDIR)
	cp $(BIN) $(BINDIR)/sidecarctl

install-app: all
	mkdir -p "$(APPDIR)"
	-osascript -e 'tell application "$(APP_NAME)" to quit' >/dev/null 2>&1
	rm -rf "$(INSTALLED_APP)"
	cp -R "$(APP_BUNDLE_PATH)" "$(INSTALLED_APP)"
	@echo "Installed $(INSTALLED_APP)"

launch-app:
	open "$(INSTALLED_APP)"

install-app-health: install-app
	$(MAKE) launch-app
	sleep 1
	$(MAKE) app-health

install-hammerspoon:
	mkdir -p $(MODULEDIR)
	cp hammerspoon/sidecar-reconnector.lua $(MODULEDIR)/sidecar-reconnector.lua

reload:
	/Applications/Hammerspoon.app/Contents/Frameworks/hs/hs -c 'hs.reload()'

unit-test: $(TEST_BIN)
	$(TEST_BIN)

test: unit-test

smoke: all
	$(BIN) list

bump-version:
	@if [ -z "$(VERSION)" ]; then \
		echo 'usage: make bump-version VERSION=0.2 [BUILD=7]' >&2; \
		exit 2; \
	fi
	@if [ -n "$(BUILD)" ]; then \
		scripts/bump-version.sh --version "$(VERSION)" --build "$(BUILD)"; \
	else \
		scripts/bump-version.sh --version "$(VERSION)"; \
	fi

bump-build:
	@scripts/bump-version.sh

release-build: bump-version clean all

dmg: all
	rm -rf "$(DMG_STAGING)" "$(DMG)"
	mkdir -p "$(DMG_STAGING)"
	cp -R "$(APP_BUNDLE_PATH)" "$(DMG_STAGING)/$(APP_NAME).app"
	ln -s /Applications "$(DMG_STAGING)/Applications"
	hdiutil create -volname "$(APP_NAME) v$(APP_VERSION)" -srcfolder "$(DMG_STAGING)" -ov -format UDZO "$(DMG)"
	@echo "Created $(DMG)"

app-health:
	@scripts/app-health.sh

clean:
	rm -rf $(BUILD_DIR)
