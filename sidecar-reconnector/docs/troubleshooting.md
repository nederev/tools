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
~/.hammerspoon/bin/sidecarctl list
```

If the iPad appears in `list`, retry:

```sh
~/.hammerspoon/bin/sidecarctl connect --name "Your iPad name"
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

## Menu-Bar App Does Nothing

Confirm the app is running by looking for the `Sidecar` menu-bar item.

Open the app log from the menu or run:

```sh
tail -f ~/Library/Logs/SidecarReconnector.log
```

If the status says `Target not configured`, open the Target submenu and
choose the iPad. The app will not reconnect without an explicit target
unless exactly one display-capable Sidecar device was discovered on
first launch.

If Launch at Login is enabled but the app does not start after login,
toggle Launch at Login off and on from the menu. The app stores its
login item in:

```text
~/Library/LaunchAgents/com.nederev.SidecarReconnector.plist
```

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
~/.hammerspoon/bin/sidecarctl list
```

If listing fails after a macOS update, the private API surface needs
to be re-investigated.
