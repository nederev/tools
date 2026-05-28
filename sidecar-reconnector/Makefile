PREFIX ?= $(HOME)/.hammerspoon
BINDIR ?= $(PREFIX)/bin
MODULEDIR ?= $(PREFIX)
BUILD_DIR ?= build
APPDIR ?= $(HOME)/Applications

CC ?= clang
CFLAGS ?= -fobjc-arc -fblocks -Wall -Wextra -Wpedantic
CLI_FRAMEWORKS := -framework Foundation
APP_FRAMEWORKS := -framework Foundation -framework AppKit -framework Carbon

BIN := $(BUILD_DIR)/sidecarctl
APP_BUNDLE := $(BUILD_DIR)/Sidecar\ Reconnector.app
APP_CONTENTS := $(APP_BUNDLE)/Contents
APP_MACOS := $(APP_CONTENTS)/MacOS
APP_BIN := $(APP_MACOS)/SidecarReconnector
APP_INFO := $(APP_CONTENTS)/Info.plist
CORE_SRC := src/SidecarController.m
CLI_SRC := src/sidecarctl.m
APP_SRC := src/SidecarReconnectorApp.m
VERSION ?=
BUILD ?=

.PHONY: all clean install install-app install-hammerspoon reload test bump-version bump-build release-build app-health

all: $(BIN) $(APP_BUNDLE)

$(BIN): $(CLI_SRC) $(CORE_SRC) src/SidecarController.h
	mkdir -p $(BUILD_DIR)
	$(CC) $(CFLAGS) $(CLI_FRAMEWORKS) $(CLI_SRC) $(CORE_SRC) -o $(BIN)

$(APP_BUNDLE): $(APP_BIN) $(APP_INFO)

$(APP_BIN): $(APP_SRC) $(CORE_SRC) src/SidecarController.h
	mkdir -p $(APP_MACOS)
	$(CC) $(CFLAGS) $(APP_FRAMEWORKS) $(APP_SRC) $(CORE_SRC) -o $(APP_BIN)

$(APP_INFO): app/Info.plist
	mkdir -p $(APP_CONTENTS)
	cp app/Info.plist $(APP_INFO)

install: all install-hammerspoon
	mkdir -p $(BINDIR)
	cp $(BIN) $(BINDIR)/sidecarctl

install-app: all
	mkdir -p "$(APPDIR)"
	rm -rf "$(APPDIR)/Sidecar Reconnector.app"
	cp -R "$(BUILD_DIR)/Sidecar Reconnector.app" "$(APPDIR)/Sidecar Reconnector.app"

install-hammerspoon:
	mkdir -p $(MODULEDIR)
	cp hammerspoon/sidecar-reconnector.lua $(MODULEDIR)/sidecar-reconnector.lua

reload:
	/Applications/Hammerspoon.app/Contents/Frameworks/hs/hs -c 'hs.reload()'

test: all
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

app-health:
	@scripts/app-health.sh

clean:
	rm -rf $(BUILD_DIR)
