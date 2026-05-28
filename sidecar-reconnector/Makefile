PREFIX ?= $(HOME)/.hammerspoon
BINDIR ?= $(PREFIX)/bin
MODULEDIR ?= $(PREFIX)
BUILD_DIR ?= build

CC ?= clang
CFLAGS ?= -fobjc-arc -fblocks -Wall -Wextra -Wpedantic
FRAMEWORKS := -framework Foundation

BIN := $(BUILD_DIR)/sidecarctl
SRC := src/sidecarctl.m

.PHONY: all clean install install-hammerspoon reload test

all: $(BIN)

$(BIN): $(SRC)
	mkdir -p $(BUILD_DIR)
	$(CC) $(CFLAGS) $(FRAMEWORKS) $(SRC) -o $(BIN)

install: all install-hammerspoon
	mkdir -p $(BINDIR)
	cp $(BIN) $(BINDIR)/sidecarctl

install-hammerspoon:
	mkdir -p $(MODULEDIR)
	cp hammerspoon/sidecar-reconnector.lua $(MODULEDIR)/sidecar-reconnector.lua

reload:
	/Applications/Hammerspoon.app/Contents/Frameworks/hs/hs -c 'hs.reload()'

test: all
	$(BIN) list

clean:
	rm -rf $(BUILD_DIR)
