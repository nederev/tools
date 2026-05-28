# Agent Install Runbook

This runbook is for an agent installing or debugging Sidecar
Reconnector on a user's Mac.

## Goal

Install a command-line helper and optional Hammerspoon watcher that
reconnects Sidecar after wake/unlock without opening Control Center.

## Requirements

- macOS with Sidecar support
- iPad signed into the same Apple ID
- Wi-Fi and Bluetooth enabled
- Xcode Command Line Tools
- Hammerspoon, for wake/unlock automation and hotkeys

Install Hammerspoon if it is missing:

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
5. Check `~/.hammerspoon/sidecar-reconnector.log`.

The watcher should run `sidecarctl connect` without opening Control
Center.

## Common Failures

`target-not-found` means Sidecar discovery did not see the iPad.
Wake/unlock the iPad and retry.

`displayAgentConnectToDevice:withConfig:completion:` selector errors
usually mean the local XPC protocol declaration is incomplete.
Check `src/sidecarctl.m` before changing method declarations.

If `sidecarctl list` works but Hammerspoon does nothing, verify:

```sh
ls -l ~/.hammerspoon/bin/sidecarctl
ls -l ~/.hammerspoon/sidecar-reconnector.lua
```

Then reload Hammerspoon and inspect the log.
