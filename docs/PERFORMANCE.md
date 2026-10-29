# Performance and verification

## Design

Drift passes video-only AVMutableComposition assets to AVQueuePlayer and AVPlayerLooper, and presents them with AVPlayerLayer. AVFoundation chooses the decoding path supported by the codec and Mac; hardware decoding is not guaranteed for every file.

There is one queue and layer per enabled display, so each display can pause independently. More displays can therefore increase decoder work and memory use. Disable unneeded displays in Settings.

The engine observes window occlusion, screen changes, sleep/wake, session changes, thermal state, Low Power Mode and IOKit power-source changes. It does not use a timer, capture the screen, inspect other apps' window titles or update SwiftUI on every video frame. All UI state and window/player lifetime changes stay on the main actor. Track metadata loading and library file copying run asynchronously away from the UI actor.

Thumbnails load on demand, rather than preloading the full library. Their NSCache has a 32 MiB cost target and 64-item limit; macOS manages eviction. These are preview cache limits, not a claim about the app's total memory use.

Pausing retains the current frame and player resources for quick resumption. It does not promise to release all decoder memory. Quitting releases the players and desktop windows.

## What the app does not do

- It does not cap the FPS or downscale an imported local file at playback time. Local files play at their encoded cadence and resolution. AVPlayerItem's preferredMaximumResolution is an HLS preference, not a local-file optimization, so Drift does not use it as one.
- It does not automatically transcode imports. Video quality and encoding determine much of the cost.
- It does not claim a universal CPU, RAM or battery number.
- It does not prevent the display from sleeping.

For a lower-cost wallpaper, encode a short seamless H.264/HEVC loop at 1920×1080, 24–30 fps. The bundled demo is 1280×720, 24 fps, 8 seconds and contains no audio. The library flags videos above 2560×1600 or about 30 fps as potentially expensive.

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

Occlusion is reported by macOS, which may count transparent or nonrectangular windows as visible. Stage Manager and Spaces behavior should be checked on each supported macOS release. The app intentionally avoids private APIs for desktop or lock-screen integration.

Automated tests cover playback policy, pause precedence/recovery, independent display decisions, persistence, selection deletion, manifest versioning and path traversal rejection. GUI, energy and hardware/OS combinations still require the manual checks above.
