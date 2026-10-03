# Changelog

## 1.0.1 - 2026-10-03

### Fixed

- Automatically run first-time setup when the Twitch channel or bot username is missing, without requiring terminal detection. After setup, continue to Twitch authorization when needed.
- Stop startup with recovery instructions when setup is cancelled, input is unavailable, or configuration cannot be read.
- Skip automatic setup when the Twitch bot is explicitly disabled.
