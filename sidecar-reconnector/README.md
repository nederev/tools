# Sidecar Reconnector

Reconnect a Mac to an iPad Sidecar display after wake or unlock,
without opening Control Center and without UI scripting.

The command-line helper uses Apple private Sidecar APIs from
`SidecarCore.framework`. The native menu-bar app watches wake/unlock
and display events, then reconnects the configured Sidecar display
when it is missing. A legacy Hammerspoon module remains available for
users who already rely on Hammerspoon.

## Status

Tested on macOS 15.7.7 with an M3 Mac and an iPad Air.

This is a private API utility. It can break after macOS updates.

## Menu-Bar App

Build the app and CLI:

```sh
make clean all
```

This produces:

```text
build/sidecarctl
build/Sidecar Reconnector.app
```

Install the app into `~/Applications`:

```sh
make install-app
```

Launch `~/Applications/Sidecar Reconnector.app`. The app runs as a
menu-bar item named `Sidecar` and has no Dock icon.

The menu includes:

- current Sidecar status
- reconnect now
- target iPad selection from discovered Sidecar devices
- launch at login toggle
- open log
- quit

On first launch, if exactly one display-capable Sidecar device is
discoverable, the app selects it automatically. If multiple devices are
discoverable, choose the target from the menu before reconnecting.

Logs are written to:

```text
~/Library/Logs/SidecarReconnector.log
```

## Hammerspoon Install

Hammerspoon is no longer required for the default app flow. Use this
section only if you want the legacy Hammerspoon watcher.

Install [Hammerspoon](https://www.hammerspoon.org/) first if you
want wake/unlock automation and hotkeys.

With Homebrew:

```sh
brew install --cask hammerspoon
open -a Hammerspoon
```

Clone the repo:

```sh
git clone https://github.com/nederev/tools.git
cd tools/sidecar-reconnector
```

Make sure Xcode Command Line Tools are installed:

```sh
xcrun --find clang
```

If that fails:

```sh
xcode-select --install
```

Then build and install the legacy helper and module:

```sh
make clean all
make install
```

Add this to `~/.hammerspoon/init.lua`:

```lua
local sidecar = require("sidecar-reconnector")

sidecar.setup({
  targetName = "Your iPad name",
  targetIdentifier = nil,
})
```

Reload Hammerspoon:

```sh
make reload
```

## CLI-Only Use

Hammerspoon is optional. The core helper can be used directly:

```sh
make clean all
build/sidecarctl list
build/sidecarctl connect --name "Your iPad name"
```

Without the menu-bar app or Hammerspoon you do not get wake/unlock
automation.

## Find Your iPad

Run:

```sh
~/.hammerspoon/bin/sidecarctl list
```

Example output:

```text
candidate name=My iPad identifier=... model=iPad16,10 desc=IDS ...
```

Use either `targetName` or `targetIdentifier` in the Hammerspoon
config. Name is easier; identifier is more stable.

## Manual Test

Disconnect Sidecar, then run:

```sh
~/.hammerspoon/bin/sidecarctl connect --name "Your iPad name"
```

Expected success:

```text
target-found name=Your iPad name ...
connect-request-ok
```

Or use the default hotkey:

```text
ctrl + alt + cmd + u
```

## Menu-Bar App Behavior

The app:

- checks whether Sidecar is already connected
- no-ops when connected
- reconnects after wake/unlock or display changes when disconnected
- retries after 8, 15, and 30 seconds because iPads can be slow to wake
- logs to `~/Library/Logs/SidecarReconnector.log`
- can install or remove its own launch-at-login entry

## Hammerspoon Behavior

The module:

- checks whether Sidecar is already connected
- no-ops when connected
- reconnects after wake/unlock when disconnected
- retries a few times because iPads can be slow to wake
- logs to `~/.hammerspoon/sidecar-reconnector.log`

Default hotkeys:

- `ctrl + alt + cmd + u`: run reconnect now
- `ctrl + alt + cmd + d`: dump display state to the log

## Why It Says AirPlay

macOS often names the virtual display `Sidecar Display (AirPlay)`.
That is an internal transport/display label. This tool does not drive
the AirPlay menu or Control Center UI.

## Uninstall

Remove these files:

```sh
rm ~/.hammerspoon/bin/sidecarctl
rm ~/.hammerspoon/sidecar-reconnector.lua
```

Then remove the `require("sidecar-reconnector")` block from
`~/.hammerspoon/init.lua` and reload Hammerspoon.

## Troubleshooting

See [docs/troubleshooting.md](docs/troubleshooting.md).

## Agent Runbook

Agents should follow [docs/agent-install.md](docs/agent-install.md)
for a from-scratch install, validation, and debugging flow.
