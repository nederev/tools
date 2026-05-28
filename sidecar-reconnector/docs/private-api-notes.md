# Private API Notes

This utility intentionally uses private macOS Sidecar APIs.

The important pieces observed on macOS 15.7.7:

- `/System/Library/PrivateFrameworks/SidecarCore.framework`
- `SidecarDisplayManager`
- `SidecarDevice`
- `com.apple.sidecar-display-agent`

The helper checks `SidecarDisplayManager.connectedDevices` first.
If the target is already connected, it exits successfully without
changing anything.

The native app wraps the same controller logic. App-level wake/session
monitoring, the global reconnect hotkey, launch-at-login checkbox, and
compact control panel are normal macOS APIs; the private API boundary is
the Sidecar discovery/status/connect behavior.

For discovery, it combines:

- `SidecarDisplayManager.devices`
- `SidecarDisplayManager.recentDevices`
- `SidecarDevice.allDevicesByForcingFetchFromRelay:YES`
- `SidecarDevice.allDevices`
- `displayAgentDevices:` over `com.apple.sidecar-display-agent`

For connection, it calls:

```objc
-[SidecarDisplayManager connectToDevice:completion:]
```

The XPC protocol declaration includes the display-agent connect and
disconnect selectors because `SidecarDisplayManager` uses that agent
internally. If the local Objective-C protocol shadows Apple's protocol
but omits those selectors, the helper can crash with:

```text
displayAgentConnectToDevice:withConfig:completion:
unrecognized selector
```

The helper declares those selectors to keep NSXPC method validation
compatible with the agent.
