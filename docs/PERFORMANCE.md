# Performance and verification

## Design

Drift passes video-only AVMutableComposition assets to AVQueuePlayer and AVPlayerLooper, and presents them with AVPlayerLayer. AVFoundation chooses the decoding path supported by the codec and Mac; hardware decoding is not guaranteed for every file.

There is one queue and layer per enabled display, so each display can pause independently. More displays can therefore increase decoder work and memory use. Disable unneeded displays in Settings.

The engine observes window occlusion, screen changes, sleep/wake, session changes, thermal state, Low Power Mode and IOKit power-source changes. It does not use a timer, capture the screen, inspect other apps' window titles or update SwiftUI on every video frame. All UI state and window/player lifetime changes stay on the main actor. Track metadata loading and library file copying run asynchronously away from the UI actor.

Thumbnails load on demand, rather than preloading the full library. Their NSCache has a 32 MiB cost target and 64-item limit; macOS manages eviction. These are preview cache limits, not a claim about the app's total memory use.

Pausing retains the current frame and player resources for quick resumption. It does not promise to release all decoder memory. Quitting releases the players and desktop windows.

All app copies share a kernel file lease held for the process lifetime. Only the owner creates a wallpaper engine; a duplicate launch activates the owner and exits. Legacy releases are terminated at startup before replacement windows are shown. Engine start is idempotent. Renderer stop cancels loading, detaches its layer and queue, removes the content view and closes the window; stopped renderers cannot restart.

System-background stills are separate from video playback. A selected frame or photo is generated once on a utility task, fitted to each display and cached as a PNG. Requests use cancellation and a generation identifier, so a stale result cannot replace a newer choice. The system image is set through NSWorkspace on the main actor. No per-frame Lock Screen rendering or privileged/loginwindow integration is used.

## Quality controls

- Original resolution and FPS are the defaults. They preserve source quality without a video compositor; high-resolution and high-FPS sources are not restricted to the lightweight demo's 720p / 24 FPS.
- Resolution maximums are 1080p, 1440p and 4K. Frame-rate maximums are 24, 30, 60 and 120 FPS. Original does not impose either cap. The plan never upscales or increases source FPS.
- A lower cap uses AVMutableVideoComposition renderSize / frameDuration only when it actually changes the source. Rotation and aspect ratio are preserved. A resolution-only cap retains source track timing. A frame-rate cap changes output cadence, not playback speed.
- Video composition may add GPU work; lower output resolution does not necessarily reduce source decoding cost. No claim is made that a particular cap saves energy. AVPlayerItem's preferredMaximumResolution is an HLS preference and is not used to pretend to optimize local files.
- It does not automatically transcode imports. Video quality and encoding determine much of the cost.
- It does not claim a universal CPU, RAM or battery number.
- It does not prevent the display from sleeping.

For a lower-cost wallpaper, encode a short seamless H.264/HEVC loop at 1920×1080, 24–30 fps. The default demo is 1280×720, 24 fps, 8 seconds. The optional Aurora 4K demo is 3840×2160, 60 fps, 8 seconds. Both are original and contain no audio. Higher-resolution and higher-FPS clips are labeled in the library. Actual smoothness also depends on display refresh rate and decoding/rendering performance.

## Reproducible manual checks

Use a release build, close the library window, and record Mac model, macOS version, power source, display count/resolution/refresh rate, codec, dimensions, frame rate and duration. Activity Monitor's CPU figure is per logical core and is not a whole-device power measurement. Use Instruments' Time Profiler / Energy tools for deeper investigation.

| Scenario | Expected result |
| --- | --- |
| Visible desktop, Aurora | Continuous, silent loop; icons remain clickable |
| Fully cover one display with an opaque window | That display pauses when AppKit reports it occluded |
| Reveal the desktop | Playback resumes, unless a higher-priority pause condition remains |
| Pause manually, cover and uncover | Remains manually paused |
| Sleep/wake display | Pauses during sleep; resumes after wake if allowed |
| Enable Low Power Mode | Pauses with the setting enabled |
| Unplug power with battery pause enabled | Pauses; resumes on AC |
| Full-screen app / Space switch | Desktop stays behind apps; occluded displays pause |
| Disconnect/reconnect a display | Retired queue is torn down; current display geometry is rebuilt |
| Remove selected clip / turn wallpapers off | Windows and queues are removed; system wallpaper reappears |
| Quit Drift | No wallpaper windows, decoding, timers or helper processes remain |
| Relaunch | Library, selection, fit and manual pause state persist |
| Change English / Russian | Labels and menu actions update immediately; choice persists |
| Load a 1.0 library | Media, selection, manual pause and display settings survive migration |
| Click button edges | Full visible navigation and Add video shapes respond |
| Aurora 4K, Original | 3840×2160 / 60 FPS, without an attached video composition |
| Aurora 4K, 1080p / 30 FPS | 1920×1080 / 30 FPS, with unchanged playback speed |
| 720p / 24 FPS with 4K / 120 limits | Stays 720p / 24 FPS, without extra composition |
| Start a second installed/downloaded copy | Existing owner remains; second exits without creating desktop windows |
| Switch videos rapidly while metadata is loading | Old queues/layers are detached and canceled windows stay closed |
| Apply a video still or photo | Current-space system image changes; appearance on the secure Lock Screen is determined by macOS |
| Restore the system image | Saved URLs/options restore where supported; a newer manual picture is preserved |
| Enable first-frame sync and change video | Latest selection applies once; obsolete requests never change the system image |

Occlusion is reported by macOS, which may count transparent or nonrectangular windows as visible. Stage Manager and Spaces behavior should be checked on each supported macOS release. The app intentionally avoids private APIs for desktop or lock-screen integration.

Automated tests cover pause policy, persistence/migration, path traversal, quality planning, 4K60 metadata, rendered output, localization, exclusive ownership, restoration journaling, manual-change preservation, disconnected displays, failed system writes and terminal renderer cancellation. Tests use a fake workspace for system-image mutations. Media tests need macOS video services. GUI, Lock Screen visuals, energy and hardware/OS combinations still require manual verification. The static-image API cannot restore complete aerial/dynamic/shuffle configurations.
