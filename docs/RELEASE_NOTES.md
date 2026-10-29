Drift 1.2.0 — one wallpaper owner, plus system-background stills for macOS.

- Only one Drift copy owns desktop playback. Repeated launches show the existing library and exit; old legacy copies are retired before replacement players start.
- Stopped renderers detach their layers/queues and cannot reopen after canceled loading.
- New Settings → Lock Screen & system background section: apply a selected video frame or photo, optionally follow video selection, and restore prior system image URLs/options.
- System-image restoration is journaled atomically, preserves newer manual pictures, and retains records for disconnected displays.
- Stills are generated on a utility task, fitted to each display and cached. Superseded requests cannot change the system image.
- English and Russian interfaces; existing libraries and preferences migrate automatically.

**Lock Screen scope:** this sets a static macOS desktop picture that macOS may also use on the secure Lock Screen. It also changes the system desktop picture underneath Drift. It is not an independent animated Lock Screen and does not customize FileVault/login screens, replace aerial assets or modify loginwindow. Use macOS Wallpaper settings for dynamic/aerial modes and other spaces. Restoring an image cannot restore a complete dynamic/shuffle configuration.

Download `Drift-universal.zip`, unzip and move Drift to Applications. Requires macOS 13+, Apple Silicon or Intel. The build is ad-hoc signed and not Apple-notarized; standard macOS first-launch trust checks may apply. Verify the included SHA256SUMS.txt. Drift does not add confirmation dialogs for its own background changes or instance handoff.
