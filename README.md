# TF2Client

Twitch chatbot for a Transport Fever 2 Twitch integration mod.

It connects to Twitch chat via `tmi`, writes request `.lua` files for the game mod to process, and polls `*.json` response files to reply in chat.

## Setup

### Twitch Developer Application (OAuth)

To use the OAuth bootstrap/refresh flow you need to create a Twitch Developer application:

1. Go to `https://dev.twitch.tv/console/apps` and create a new application.
2. Set the OAuth Redirect URL to `http://localhost:4000/oauth/callback` (must match `TWITCH_REDIRECT_URI`).
3. Copy the `Client ID` and generate/copy the `Client Secret`.
4. Set `TWITCH_CLIENT_ID` and `TWITCH_CLIENT_SECRET` in your environment.

If you rotate the client secret or revoke access, delete the stored token file and run the bootstrap again.

### Environment variables

- `TWITCH_BOT_USER`: bot Twitch username (lowercase recommended)
- `TWITCH_BOT_OAUTH` (optional): bot OAuth token for IRC (must start with `oauth:`); if unset, uses the stored OAuth tokens
- `TWITCH_CHANNELS`: comma/space separated list of channels to join (no `#`)
- `TWITCH_MOD_CHANNELS` (optional): channels where the bot is a moderator (rate limits)
- `TWITCH_DEBUG` (optional): `true`/`false`
- `TF2_INTEGRATION_GAME_FILES` (optional): folder shared with the game mod (contains `requests.txt`, `gameState.json`, and response files). If unset or empty, the bot uses `~/.tf2`, matching the game mod.
- `TF2_ENABLE_TWITCH_BOT` (optional): set to `false` to disable starting the bot
- `TF2_DISABLE_RATE_LIMITS` (optional): set to `true` to disable rate limiting
- `TF2_REQUEST_QUEUE_DELAYS_MS` (optional): per-request delays (e.g. `TOWN=5000,COMPANY=0,LINE=0,VEHICLE=0`). Requests with `0` delay are sent immediately; delayed types are queued FIFO.
- `TWITCH_CLIENT_ID`: Twitch OAuth client id (required for OAuth bootstrap/refresh)
- `TWITCH_CLIENT_SECRET`: Twitch OAuth client secret (required for OAuth bootstrap/refresh)
- `TWITCH_REDIRECT_URI`: OAuth redirect URI (default: `http://localhost:4000/oauth/callback`)

### Run

Start the game with the mod enabled so it can create/update `gameState.json` in the shared game files folder, then run:

`iex -S mix`

By default the bot joins the configured channels but does not send any chat messages until enabled by a moderator/broadcaster.

### OAuth bootstrap (one-time)

Run:

`mix twitch.oauth.bootstrap`

For the packaged Burrito executable, run:

`.\tf2_client_windows.exe oauth.bootstrap`

#### Releases

Mix tasks are not available in releases. To bootstrap in a release, run:

`bin/tf2_client eval "TF2Client.Twitch.OAuthBootstrap.bootstrap!()"`

Notes:

- This opens a local browser and listens on `http://localhost:4000/oauth/callback`.
- Tokens are stored at `~/.config/tf2_client/twitch_tokens.json` by default.
- For headless servers, run the bootstrap on a machine with a browser and copy the token file to the server user.

### Packaged Windows executable

Burrito is configured with a Windows x64 target named `windows`.

Build from Linux, macOS, or Windows through WSL:

`MIX_ENV=prod BURRITO_TARGET=windows mix release`

The distributable executable is written to:

`burrito_out/tf2_client_windows.exe`

Burrito production binaries unpack the embedded release on first run and reuse that unpacked payload for later runs of the same app version. If you rebuild with code changes but keep the same `version` in `mix.exs`, Windows may keep running the previously unpacked code. For normal releases, bump the project version before building. For local verification of a rebuilt same-version binary, run:

`.\tf2_client_windows.exe maintenance uninstall`

Then start the executable again so Burrito unpacks the new payload. You can inspect the unpacked runtime path with:

`.\tf2_client_windows.exe maintenance directory`

Build machine requirements:

- `zig` 0.15.2
- `xz`
- `7z` or `7zz` for Windows targets

The Windows machine running the executable does not need Elixir or Erlang installed. It does need the MSVC runtime required by the bundled Erlang runtime and Windows 10 build 1511 or newer.

If Windows shows `VCRUNTIME140.dll was not found`, install the Microsoft Visual C++ Redistributable x64 package from `https://aka.ms/vc14/vc_redist.x64.exe`.

Set the environment variables before starting the bot. In PowerShell:

```powershell
$env:TWITCH_BOT_USER = "your_bot_username"
$env:TWITCH_CHANNELS = "streamer_channel"
$env:TWITCH_CLIENT_ID = "your_client_id"
$env:TWITCH_CLIENT_SECRET = "your_client_secret"
.\tf2_client_windows.exe
```

TF2Client packaged commands:

- `.\tf2_client_windows.exe oauth.bootstrap`

Burrito maintenance commands:

- `.\tf2_client_windows.exe maintenance directory`
- `.\tf2_client_windows.exe maintenance uninstall`

## Chat commands

- `!tf2on` → enable the bot in chat (mods/broadcaster only)
- `!tf2off` → disable the bot in chat (mods/broadcaster only)
- `!pause <claim|town|line|vehicle|all>` → pause a redemption type (mods/broadcaster only)
- `!resume <claim|town|line|vehicle|all>` → resume a redemption type (mods/broadcaster only)
- `!paused` → list paused redemption types (mods/broadcaster only)
- `!claim [company name]` → create/claim company
- `!town [company name]` → purchase/assign a town
- `!line <carrier> <cargo>` → purchase/assign a transport line
- `!vehicle <carrier> <cargo>` → purchase/assign a vehicle
- `!profit` → show your total profit
- `!vehicles` → show how many vehicles you own
- `!rank` → show top players by profit
- `!carriers` → list valid carrier types
- `!cargo` → list valid cargo types
- `!help` → show help

Valid carriers: `AIR`, `RAIL`, `ROAD`, `WATER`, `TRAM`.

## Local simulator (no Twitch)

Run an interactive shell that simulates chat messages and prints bot replies:

`mix tf2.sim`

If `TF2_INTEGRATION_GAME_FILES` is unset or empty, it uses a fresh temp folder and prints the path on start.
Type `:help` in the sim for commands. Use `:play <path> [delay_ms]` to replay a script of chat lines, `:delay <ms>` to pause before the next command, and `:ratelimit off` to disable rate limiting.

## File protocol (with the game mod)

- Shared folder: `TF2_INTEGRATION_GAME_FILES` when set and non-empty, otherwise `~/.tf2`; if no home folder is available, `<temp>/tf2`.
- Bot writes: `#{order_id}.lua` (Lua `return` table with `schema_version = 1`) and appends `order_id` to `requests.txt`.
- Mod writes: `#{order_id}.json` responses; the bot reads, replies in chat, then deletes the response file (and the request `.lua` on completion).
