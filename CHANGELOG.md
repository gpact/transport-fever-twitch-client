# Changelog

## 1.1.0 - 2026-10-04

### Changed

- Improved the user's Twitch authorization workflow.

## 1.0.2 - 2026-10-03

### Fixed

- Show filesystem errors in the dashboard and status API, distinguishing missing files from other access failures. Keep the resolved game-state path in the API only to avoid exposing local usernames on the dashboard.
- Report invalid JSON and missing save identifiers instead of showing a misleading game connection.

## 1.0.1 - 2026-10-03

### Fixed

- Automatically run first-time setup when the Twitch channel or bot username is missing, without requiring terminal detection. After setup, continue to Twitch authorization when needed.
- Stop startup with recovery instructions when setup is cancelled, input is unavailable, or configuration cannot be read.
- Skip automatic setup when the Twitch bot is explicitly disabled.
