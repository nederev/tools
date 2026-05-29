# Tools Agent Guide

This repository contains standalone utilities. Keep tools isolated from
each other unless shared code is clearly necessary.

## Sidecar Reconnector

Use `sidecar-reconnector/docs/agent-install.md` when installing,
testing, or modifying the Sidecar Reconnector on a user's Mac.

Important boundaries:

- The Objective-C helper uses private macOS Sidecar APIs.
- Do not claim compatibility across macOS releases without testing.
- Do not hardcode a user's iPad name or identifier in committed files.
- Keep generated binaries out of git; `build/` is ignored.
- Prefer `make -C sidecar-reconnector clean all` for validation.
- Use the Make targets below instead of editing plist versions or
  install paths ad hoc.

Agent command quick reference:

```sh
# Build CLI and native app.
make -C sidecar-reconnector clean all

# Run device-independent unit tests for the resolver logic.
make -C sidecar-reconnector test

# Bump the visible app version and increment CFBundleVersion.
make -C sidecar-reconnector bump-version VERSION=0.2

# Bump only CFBundleVersion.
make -C sidecar-reconnector bump-build

# Set both visible version and build number explicitly.
make -C sidecar-reconnector bump-version VERSION=0.2 BUILD=7

# Bump version, clean, and rebuild in one command.
make -C sidecar-reconnector release-build VERSION=0.2

# Install app, launch it, then run the health check.
make -C sidecar-reconnector install-app-health

# Create a simple unsigned DMG under build/.
make -C sidecar-reconnector dmg

# Inspect installed app path/version, process state, LaunchAgent, log,
# hotkey registration evidence, and target preference.
make -C sidecar-reconnector app-health
```

Menu-bar app / Dock behavior:

- The app is a menu-bar-only ("agent") app: `LSUIElement` is `true` and the
  code asserts `NSApplicationActivationPolicyAccessory` at launch. There is no
  Dock icon and no Dock toggle — the control panel is a popover off the status
  item, so a Dock presence would add nothing.
- The control panel is an `NSPopover` (transient) anchored under the status
  item: left-click toggles it, right-click shows the menu. A `popoverDidClose`
  timestamp + `PopoverReopenGuard` window in `togglePopover` avoids the
  click-to-open / transient-dismiss race. It does not auto-open on launch.
- Device discovery (`listDevicesWithError:`) does blocking XPC, so it MUST run
  off the main thread. `refreshAsyncAllowAutoSelect:` fetches the device list
  once on a background queue, then updates the target menu/popup AND the status
  on the main thread from that one list (status is derived with the pure
  `resolveTarget:devices:` — no second discovery). Do not call the controller's
  list/status/connect methods on the main thread.
- Notch gotcha (verified on a notched MacBook Air): a freshly added
  `NSStatusItem` on a full menu bar gets parked under the notch and is
  invisible even though `visible == YES` and it has a valid window frame.
  Fix: set `statusItem.autosaveName` and seed
  `NSUserDefaults` key `"NSStatusItem Preferred Position <autosaveName>"`
  to `0` (rightmost slot, next to Control Center) on first run only, so the
  user can still Cmd-drag it afterwards. Lower position value = further right.
- To verify visually, `screencapture` needs the host app (e.g. the terminal
  or Claude) to have Screen Recording permission; `-R` region captures can
  return black even then, so capture full-screen and crop. If a foreground
  app is full-screen, the menu bar only renders on hover.

Versioning rules:

- The control-panel title is derived from
  `CFBundleShortVersionString`, for example
  `Sidecar Reconnector v0.15`.
- When changing visible UI or shipping a user-facing rebuild, bump the
  version or at least the build number before rebuilding.
- `scripts/bump-version.sh` owns plist edits; do not hand-edit
  `CFBundleShortVersionString` or `CFBundleVersion` unless the script is
  broken.

Release/install rules:

- `release-build` only builds a versioned app bundle under `build/`; it
  does not install into `~/Applications`.
- For a user machine install, use `make -C sidecar-reconnector install-app`
  when permissions allow it.
- For a complete local install verification, use
  `make -C sidecar-reconnector install-app-health`; it installs the app,
  launches it, waits briefly, and then runs `app-health`.
- For a shareable local artifact before signing/notarization, use
  `make -C sidecar-reconnector dmg`; the resulting DMG is unsigned.
- If sandbox permissions block `install-app`, give the user the manual
  terminal install command instead of trying unsafe workarounds.
- After install, run `make -C sidecar-reconnector app-health`.

Signing/notarization:

- Do not invent signing identities, Team IDs, or notarization profiles.
- Signed/notarized packaging requires the user's Apple Developer
  `Developer ID Application` certificate and a configured `notarytool`
  keychain profile.
- Until those values are known, describe the signing flow but do not add
  a hardcoded signed package target.

For a user machine install, the expected flow is:

```sh
make -C sidecar-reconnector clean all
make -C sidecar-reconnector install-app-health
```

Launch `~/Applications/Sidecar Reconnector.app`, choose the Sidecar
target in the compact panel, and enable `Launch at login` when the app
should start automatically after login. Hammerspoon is now legacy-only.

For the legacy Hammerspoon watcher, install the helper/module:

```sh
make -C sidecar-reconnector install
```

Then configure `~/.hammerspoon/init.lua`:

```lua
local sidecar = require("sidecar-reconnector")

sidecar.setup({
  targetName = "User iPad name",
  targetIdentifier = nil,
})
```

Reload Hammerspoon:

```sh
make reload
```

Validate:

```sh
sidecar-reconnector/build/sidecarctl list
sidecar-reconnector/build/sidecarctl status --name "User iPad name"
tail -f ~/Library/Logs/SidecarReconnector.log
```
