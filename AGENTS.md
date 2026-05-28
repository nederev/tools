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

For a user machine install, the expected flow is:

```sh
make -C sidecar-reconnector clean all
make -C sidecar-reconnector install-app
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
