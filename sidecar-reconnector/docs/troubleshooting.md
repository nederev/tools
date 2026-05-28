# Troubleshooting

## `target-not-found`

The Mac could not see the iPad through Sidecar discovery.

Check:

- iPad is awake
- iPad is near the Mac
- Wi-Fi and Bluetooth are enabled
- both devices use the same Apple ID
- Sidecar works manually from System Settings or Control Center

Then try:

```sh
build/sidecarctl list
```

If the iPad appears in `list`, retry:

```sh
build/sidecarctl connect --name "Your iPad name"
```

## iPad Is Locked

The Mac generally cannot unlock the iPad. If the iPad is asleep or
locked, Sidecar discovery may lag or fail.

The Hammerspoon module retries after wake/unlock. If it still fails,
wake or unlock the iPad and press:

```text
ctrl + alt + cmd + u
```

## Hammerspoon Does Nothing

Confirm the module is loaded:

```sh
/Applications/Hammerspoon.app/Contents/Frameworks/hs/hs -c 'print(SidecarReconnector ~= nil)'
```

Check the log:

```sh
tail -f ~/.hammerspoon/sidecar-reconnector.log
```

## Native App Does Nothing

Confirm the app is running by looking for the compact `Sidecar
Reconnector` window, the Dock icon, or the `Sidecar` menu-bar item.

Open the app log from the menu or run:

```sh
tail -f ~/Library/Logs/SidecarReconnector.log
```

If the status says `Target not configured`, open the Target submenu and
choose the iPad, or choose the target from the app panel. The app will
not reconnect without an explicit target unless exactly one
display-capable Sidecar device was discovered on first launch.

If `Launch at login` is enabled but the app does not start after login,
toggle the checkbox off and on from the panel, or toggle Launch at Login
from the menu. The app stores its login item in:

```text
~/Library/LaunchAgents/com.nederev.SidecarReconnector.plist
```

If the global hotkey does not reconnect, use the edit button in the
panel to record a new shortcut. Another app may already own the selected
key combination. Check the app log for:

```text
hotkey registration failed
```

Default standalone hotkey:

```text
ctrl + alt + cmd + u
```

## Wake Or Login Automation Does Not Run

The native app must already be running to observe wake/session/display
events. Enable `Launch at login` in the panel if you want automatic
startup after login.

The app watches:

- system wake
- screen wake
- session active after unlock
- display configuration changes

When one of those events fires, it schedules reconnect retries after 8,
15, and 30 seconds.

## Build Fails

Install Xcode Command Line Tools:

```sh
xcode-select --install
```

Then rebuild:

```sh
make clean
make
```

The default build should produce both:

```text
build/sidecarctl
build/Sidecar Reconnector.app
```

## macOS Update Broke It

This tool uses private APIs. A macOS update can rename classes,
change method signatures, or add entitlement checks.

Run:

```sh
build/sidecarctl list
```

If listing fails after a macOS update, the private API surface needs
to be re-investigated.
