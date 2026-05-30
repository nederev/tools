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

Install, launch, and run the health check in one command:

```sh
make install-app-health
```

Launch `~/Applications/Sidecar Reconnector.app`. It lives only in the menu bar
as a small display icon — there is no Dock icon. **Left-click** the icon to open
a compact control panel as a popover anchored under the menu bar; it dismisses
when you click away. **Right-click** (or control-click) the icon for a menu with
the same actions.

The control panel popover includes:

- current Sidecar target and connection status
- compact reconnect button
- a `Pause` switch (suspends automatic reconnects; see below)
- target iPad selector from discovered Sidecar devices
- refresh targets button
- configurable global reconnect hotkey
- `Launch at login` checkbox
- open log and quit buttons

The right-click menu includes the same core actions: status, reconnect now,
pause, target selection, launch-at-login toggle, show control panel, open log,
and quit.

### Pause

Flip **Pause** (the header switch, or the `Pause` item in the right-click menu)
when you want to use the iPad on its own — read on it, AirPlay a movie, etc. —
without the app pulling it back as a Sidecar display. While paused the app keeps
running but ignores wake/unlock/display-change events; the status reads `Paused`
and the menu-bar icon dims. Manual reconnect (the button, menu, or hotkey) still
works. Un-pause to resume automatic reconnection.

On first launch, if exactly one display-capable Sidecar device is
discoverable, the app selects it automatically. If multiple devices are
discoverable, choose the target from the popover before reconnecting.

Logs are written to:

```text
~/Library/Logs/SidecarReconnector.log
```

## Launch At Login

Enable `Launch at login` in the control panel or from the `Sidecar`
menu-bar item. The app writes:

```text
~/Library/LaunchAgents/com.nederev.SidecarReconnector.plist
```

Disable the checkbox to remove that LaunchAgent.

## Version Bumps

The app title reads from `CFBundleShortVersionString` in
`app/Info.plist`. Bump it before a build when you need a visibly new app
version:

```sh
make bump-version VERSION=0.2
make clean all
```

That updates `CFBundleShortVersionString` and increments
`CFBundleVersion`. To bump only the build number:

```sh
make bump-build
make clean all
```

For an explicit version and build number:

```sh
make bump-version VERSION=0.2 BUILD=7
```

For a one-command versioned build:

```sh
make release-build VERSION=0.2
```

## DMG Package

Create a simple unsigned DMG for local sharing or manual install:

```sh
make dmg
```

This produces:

```text
build/Sidecar-Reconnector-vX.Y.dmg
```

The DMG contains `Sidecar Reconnector.app` and an `Applications` shortcut.
It is not signed or notarized yet, so macOS may still show Gatekeeper
warnings on other machines.

## Health Check

After installing or debugging the app, run:

```sh
make app-health
```

The health check reports:

- installed app path and version
- app process state
- LaunchAgent target
- log freshness
- hotkey registration evidence from the app log
- configured target preference

## Tests

Run the device-independent unit tests for the target-resolution logic
(exact/fuzzy matching, ambiguity, and auto-select). These do not touch the
private Sidecar APIs and need no attached iPad:

```sh
make test
```

To smoke-test discovery against real hardware instead:

```sh
make smoke
```

## Hotkey

The standalone app registers a global reconnect hotkey. The default is:

```text
ctrl + alt + cmd + u
```

Use the hotkey edit button in the control panel to record a different
shortcut. The hotkey raises the panel and runs reconnect quietly without
showing an alert when Sidecar is already connected.

## Hammerspoon Install

Hammerspoon is no longer required for the default app flow. Use this
section only if you want the legacy Hammerspoon watcher.

Install [Hammerspoon](https://www.hammerspoon.org/) first if you want
the legacy watcher instead of the native app.

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
build/sidecarctl list
```

Example output:

```text
candidate name=My iPad identifier=... model=iPad16,10 desc=IDS ...
```

Use either `targetName` or `targetIdentifier` in the Hammerspoon
config, or choose the target in the native app. Name is easier;
identifier is more stable.

## Manual Test

Disconnect Sidecar, then run:

```sh
build/sidecarctl connect --name "Your iPad name"
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
- skips all automatic reconnects while `Pause` is on (manual still works)
- logs to `~/Library/Logs/SidecarReconnector.log`
- can install or remove its own launch-at-login entry from the control
  panel checkbox or menu item
- registers a configurable global reconnect hotkey

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

For the native app, quit Sidecar Reconnector and remove:

```sh
rm -rf ~/Applications/Sidecar\ Reconnector.app
rm -f ~/Library/LaunchAgents/com.nederev.SidecarReconnector.plist
rm -f ~/Library/Logs/SidecarReconnector.log
```

For the legacy Hammerspoon install, remove these files:

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
