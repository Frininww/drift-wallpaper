# Drift

**A quieter desktop.** Native, energy-conscious video wallpapers for macOS 13+, built with SwiftUI, AppKit and AVFoundation. Apple Silicon and Intel. The app interface is currently in Russian.

[Download the latest release](https://github.com/Frininww/drift-wallpaper/releases/latest) · [Русский README](../README.md) · [Performance](PERFORMANCE.md)

![Drift library with the original Aurora wallpaper](preview.png)

## Features

- Import local MP4, MOV and M4V files playable by macOS. H.264 / HEVC recommended.
- Original seamless eight-second Aurora demo included; no third-party wallpaper assets.
- Independent player and occlusion pause for each enabled display, using the same selected wallpaper.
- Pauses on display/system sleep, inactive sessions, serious thermal pressure and, by default, Low Power Mode. Optional battery pause.
- Fill/fit scaling, menu bar controls, persistent library and opt-in launch at login.
- Video-only playback: audio tracks never enter the playback queue.
- No accounts, telemetry, network calls, third-party packages, Electron or frame polling.

## Install

Download `Drift-universal.zip` from [Releases](https://github.com/Frininww/drift-wallpaper/releases/latest), unzip it and move Drift to Applications. Launch it and click **Добавить видео** (Add video), then click a library card to apply it. Closing the library window keeps Drift in the menu bar. **Завершить Drift** quits; **Выключить обои** removes the video overlay and reveals your original wallpaper.

Release builds are **ad-hoc signed and not Apple-notarized**. macOS may require an explicit exception in System Settings → Privacy & Security → Open Anyway. Verify the source and `SHA256SUMS.txt` before allowing it, or build from source. Do not disable Gatekeeper globally. Screen Recording and Accessibility permissions are not required.

## Build

Requires Xcode 16+ and Swift 6+. No package downloads are needed.

```sh
git clone https://github.com/Frininww/drift-wallpaper.git
cd drift-wallpaper
swift test
bash scripts/build-app.sh --universal
open dist/Drift.app
```

Open `Package.swift` in Xcode for development. The build script packages resources and the icon, applies an ad-hoc signature and verifies the app. Set `SIGNING_IDENTITY` to your Developer ID identity for your own signed build; notarization remains a separate step requiring your Apple Developer account.

## Efficiency and limits

AVPlayerLayer displays a video-only AVMutableComposition through AVQueuePlayer / AVPlayerLooper. macOS selects the available decoding path. System notifications drive pause/resume and display reconfiguration; the app has no screen capture, window-list polling or custom frame-render loop.

One player per enabled display enables independent pausing but can increase decoder work. Prefer short seamless H.264/HEVC clips at 1080p and 24–30 fps. Drift flags expensive files; it does not transcode them or cap local-file FPS. Pausing retains player resources; turning wallpapers off or quitting releases them. No fixed CPU/RAM/battery claim is made. See [performance verification](PERFORMANCE.md).

The lock screen and macOS screen saver are not modified. Web wallpapers, streams, DRM, GIF and Wallpaper Engine projects are unsupported. Occlusion reporting depends on macOS and may behave differently with transparent windows, Spaces and Stage Manager.

## Data and development

Local data lives at `~/Library/Application Support/Drift/`: atomic `library.json` plus copied media under `Wallpapers/`. Original files are not modified. Damaged manifests are backed up before recovery.

`DriftCore` contains pause policy and storage, `Drift` contains the native UI and player engine, and `DriftCoreTests` tests policy and persistence. The initial release was built and verified locally, with all 14 automated tests passing. Ready-to-use GitHub Actions templates are in [workflows/](workflows/); move them into `.github/workflows/` and push with a credential that has `workflow` permission to enable CI and releases on `v*` tags. Automation is inactive until those templates are installed.

See [contributing](../CONTRIBUTING.md). Code, generated icon and original Aurora video are [MIT licensed](../LICENSE).
