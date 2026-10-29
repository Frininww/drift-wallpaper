# Changelog

## 1.1.0

- English by default, with an immediate, persistent Russian switch in Settings. Menus, statuses, alerts and accessibility labels follow the selected language.
- Removed the lower-left sidebar slogan.
- Matched navigation, Add video, playback and wallpaper-card hit regions to their visible shapes.
- Attached the video picker to its library window so canceling returns focus; added native Open, Close and Quit shortcuts.
- Added Original / 1080p / 1440p / 4K and Original / 24 / 30 / 60 / 120 FPS limits, with effective output shown in Settings.
- Original preserves source quality without a video compositor. Limits preserve aspect ratio and never upscale or invent frames.
- Included an optional original Aurora demo encoded at 3840×2160, 60 FPS; kept the lightweight default demo.
- Migrated existing library settings without losing imported media or selection.
- Made English the primary GitHub documentation, with a Russian README alongside it.
- Added tests for migration, quality planning, real video output and localization consistency.
- Verification: all 27 automated tests pass; language switching, full button regions, video-picker cancellation and the 4K60 demo were also checked in the running app.

## 1.0.0

- Native local-video desktop wallpapers, SwiftUI library and menu bar controls.
- Independent display players, occlusion pause and energy-aware playback.
- Atomic local storage, optional launch at login, fill/fit scaling and original Aurora demo.
