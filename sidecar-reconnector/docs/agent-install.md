# Agent Install Runbook

This runbook is for an agent installing or debugging Sidecar
Reconnector on a user's Mac.

## Goal

Install a native menu-bar app, command-line helper, and optional
Hammerspoon watcher that reconnect Sidecar after wake/unlock without
opening Control Center.

## Requirements

- macOS with Sidecar support
- iPad signed into the same Apple ID
- Wi-Fi and Bluetooth enabled
- Xcode Command Line Tools
- Hammerspoon only for the legacy optional watcher

Install Hammerspoon only if the user wants the legacy watcher:

```sh
brew install --cask hammerspoon
open -a Hammerspoon
```

Check compiler availability:

```sh
xcrun --find clang
```

If missing, ask the user to install Command Line Tools:

```sh
xcode-select --install
```

## Build

From the repository root:

```sh
make -C sidecar-reconnector clean all
```

Expected result:

```text
sidecar-reconnector/build/sidecarctl
sidecar-reconnector/build/Sidecar Reconnector.app
```

When the app UI changed and the user needs to visually distinguish a new
build, bump the visible app version before rebuilding:

```sh
make -C sidecar-reconnector bump-version VERSION=0.2
make -C sidecar-reconnector clean all
```

## Install Native App

Run:

```sh
make -C sidecar-reconnector install-app
```

This installs:

```text
~/Applications/Sidecar Reconnector.app
```

Launch the app and use the `Sidecar` menu-bar item to choose the target
iPad, or choose the target in the compact app panel. Use the `Launch at
login` checkbox in the panel when the app should start automatically
after login.

The compact panel should show:

- selected Sidecar device and connection status
- reconnect icon button
- target selector and refresh icon button
- reconnect hotkey field and edit icon button
- `Launch at login` checkbox
- open log and quit buttons

Default standalone hotkey:

```text
ctrl + alt + cmd + u
```

Validate the app log:

```sh
tail -f ~/Library/Logs/SidecarReconnector.log
```

Validate the app process:

```sh
pgrep -fl SidecarReconnector
```

Validate launch-at-login state when enabled:

```sh
test -f ~/Library/LaunchAgents/com.nederev.SidecarReconnector.plist
```

Run the bundled app health check for a single install/process/log/hotkey
summary:

```sh
make -C sidecar-reconnector app-health
```

## Discover Devices

Run:

```sh
sidecar-reconnector/build/sidecarctl list
```

Look for the iPad line:

```text
candidate name=My iPad identifier=... model=iPad... offersDisplay=true
```

Use the exact `name` or `identifier` for setup.

## Install Helper And Module

Run:

```sh
make -C sidecar-reconnector install
```

This installs:

```text
~/.hammerspoon/bin/sidecarctl
~/.hammerspoon/sidecar-reconnector.lua
```

## Configure Hammerspoon

Append this to `~/.hammerspoon/init.lua` or merge it into the
existing config:

```lua
local sidecar = require("sidecar-reconnector")

sidecar.setup({
  targetName = "My iPad",
  targetIdentifier = nil,
})
```

Use `targetIdentifier` instead of `targetName` if the user has
multiple similarly named devices.

Reload:

```sh
/Applications/Hammerspoon.app/Contents/Frameworks/hs/hs -c 'hs.reload()'
```

The reload command may print a transient message-port error while
Hammerspoon restarts. Confirm after a second:

```sh
/Applications/Hammerspoon.app/Contents/Frameworks/hs/hs -c 'print(SidecarReconnector ~= nil)'
```

## Manual Validation

Check status:

```sh
~/.hammerspoon/bin/sidecarctl status --name "My iPad"
```

Disconnect Sidecar manually, then reconnect:

```sh
~/.hammerspoon/bin/sidecarctl connect --name "My iPad"
```

Expected success:

```text
target-found name=My iPad ...
connect-request-ok
```

After a few seconds, status should become:

```text
already-connected name=My iPad ...
```

## Hammerspoon Validation

Run the same reconnect path through Hammerspoon:

```sh
/Applications/Hammerspoon.app/Contents/Frameworks/hs/hs -c 'SidecarReconnector.runReconnect("manual validation")'
```

Watch logs:

```sh
tail -f ~/.hammerspoon/sidecar-reconnector.log
```

Default hotkeys:

- `ctrl + alt + cmd + u`: reconnect now
- `ctrl + alt + cmd + d`: dump display state

## Wake/Unlock Test

1. Disconnect Sidecar.
2. Sleep the Mac.
3. Wake and unlock the Mac.
4. Wait for the configured retry delays.
5. Check `~/Library/Logs/SidecarReconnector.log` for the native app, or
   `~/.hammerspoon/sidecar-reconnector.log` for the legacy watcher.

The native app or legacy watcher should run reconnect without opening
Control Center. The native app schedules retries after wake/session/display
events at 8, 15, and 30 seconds.

## Common Failures

`target-not-found` means Sidecar discovery did not see the iPad.
Wake/unlock the iPad and retry.

`displayAgentConnectToDevice:withConfig:completion:` selector errors
usually mean the local XPC protocol declaration is incomplete.
Check `src/sidecarctl.m` before changing method declarations.

If the native app is running but does nothing, verify the target is
selected in the panel and inspect:

```sh
tail -f ~/Library/Logs/SidecarReconnector.log
```

If `sidecarctl list` works but Hammerspoon does nothing, verify:

```sh
ls -l ~/.hammerspoon/bin/sidecarctl
ls -l ~/.hammerspoon/sidecar-reconnector.lua
```

Then reload Hammerspoon and inspect the log.
