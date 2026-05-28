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
cd sidecar-reconnector
make clean all
make install
```

Then configure `~/.hammerspoon/init.lua` with:

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
~/.hammerspoon/bin/sidecarctl list
~/.hammerspoon/bin/sidecarctl status --name "User iPad name"
```
