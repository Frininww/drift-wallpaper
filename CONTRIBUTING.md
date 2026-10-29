# Contributing

Drift uses Swift 6, Swift Package Manager and system frameworks. Xcode 16 or later and macOS 13 or later are required. There are no external package dependencies.

1. Open `Package.swift` in Xcode, or run `swift build`.
2. Run `swift test` after changes to library storage or playback policy.
3. Run `bash scripts/build-app.sh` and open `dist/Drift.app` to verify the actual app bundle.
4. Check desktop icons, pause/resume, full-screen apps, screen sleep/wake and display reconnects. For engine changes also follow [PERFORMANCE.md](docs/PERFORMANCE.md).

Keep rendering event-driven. Avoid polling the window list, software frame loops and per-frame SwiftUI state updates. Do not claim a fixed CPU, memory or battery budget without measurements and hardware/media details.

The interface currently uses Russian strings. English localization is welcome. Changes should preserve keyboard access, VoiceOver descriptions and sufficient contrast.

Please describe the user-visible problem, implementation, verification and any remaining limitations in pull requests. A regression test should exercise behavior, rather than duplicate implementation details.
