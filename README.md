# TF2Client

Twitch chatbot for a Transport Fever Twitch integration mod.

It connects to Twitch chat via `tmi`, writes request `.lua` files for the game mod to process, and polls `*.json` response files to reply in chat.

## Setup

### 1. Zero-Config Twitch Login (Default)

The bot comes pre-configured with default credentials for seamless 1-click browser authorization. **You do not need to register a Twitch Developer application.**

When running the bot for the first time, simply enter your Twitch channel name. The bot will automatically open your web browser, ask you to log in with Twitch, and connect immediately!

*(Optional for Developers)*: If you prefer to manage your own Twitch application, you can still register one at `https://dev.twitch.tv/console/apps` (set OAuth Redirect URL to `http://localhost:4000/oauth/callback`) and configure your custom `client_id` and `client_secret`.

### 2. Configuration

TF2Client supports three ways to configure settings (evaluated in order of precedence):
1. **Environment variables** (highest priority, great for Docker/headless environments)
2. **`config.json` file** (checked in `./config.json` or `~/.config/transport_fever/config.json`)
3. **Interactive Setup Wizard** (prompts you on first launch if unconfigured)

#### Quick Setup via Interactive Wizard
If you start the bot without any prior configuration in a terminal, it will guide you through setting up your channel and credentials:

```bash
# On Linux / macOS:
mix tf2.setup

# On Windows executable:
.\tf2_client_windows.exe setup
```

#### Configuration File (`config.json`)
Copy `config.example.json` to `config.json` in the same directory as the executable (or place it at `~/.config/transport_fever/config.json`):

```json
{
  "bot_user": "your_bot_username",
  "channels": ["streamer_channel"],
  "client_id": "your_client_id",
  "client_secret": "your_client_secret",
  "mod_channels": [],
  "debug": false,
  "redirect_uri": "http://localhost:4000/oauth/callback"
}
```

To inspect your current configuration and token status:
# On Linux / macOS:
mix tf2.config

# On Windows executable:
.\tf2_client_windows.exe config

#### Environment variables (optional overrides)

- `TWITCH_BOT_USER`: bot Twitch username (lowercase recommended)
- `TWITCH_BOT_OAUTH` (optional): bot OAuth token for IRC (must start with `oauth:`); if unset, uses the stored OAuth tokens
- `TWITCH_CHANNELS`: comma/space separated list of channels to join (no `#`)
- `TWITCH_CLIENT_ID`: Twitch OAuth client id (required for OAuth authorization and refresh)
- `TWITCH_CLIENT_SECRET`: Twitch OAuth client secret (required for OAuth authorization and refresh)
- `TWITCH_REDIRECT_URI` (optional): OAuth redirect URI (default: `http://localhost:4000/oauth/callback`)
- `TWITCH_MOD_CHANNELS` (optional): channels where the bot is a moderator (rate limits)
- `TWITCH_DEBUG` (optional): `true`/`false`
- `TF_CONFIG_PATH`: custom path to `config.json`
- `TF_INTEGRATION_GAME_FILES`: folder shared with the game mod (contains `requests.txt`, `gameState.json`, and response files). If unset or empty, the bot uses `~/.transport_fever`, matching the game mod.
- `TF_ENABLE_TWITCH_BOT`: set to `false` to disable starting the bot
- `TF_DISABLE_RATE_LIMITS`: set to `true` to disable rate limiting
- `TF_REQUEST_QUEUE_DELAYS_MS` (optional): per-request delays (e.g. `TOWN=5000,COMPANY=0,LINE=0,VEHICLE=0`). Requests with `0` delay are sent immediately; delayed types are queued FIFO.

### 3. Run & Auto-Authorization

Start the game with the mod enabled so it can create/update `gameState.json` in the shared game files folder, then run:

```bash
# On Linux / macOS (foreground):
mix run --no-halt

# Or interactive IEx shell:
iex -S mix

# On Windows executable:
.\tf2_client_windows.exe
```

- **Seamless Auto-Authorization**: If tokens are not present, the bot automatically opens your browser to authorize with Twitch, saves the credentials to `~/.config/transport_fever/twitch_tokens.json`, and connects to chat immediately without requiring a restart!
- By default the bot joins the configured channels but does not send any chat messages until enabled by a moderator/broadcaster with `!tfon`.

#### Streamer Control Panel (`http://localhost:4000`)

When the bot runs, it automatically serves a lightweight Streamer Control Panel at `http://localhost:4000`:
- **Live Status Badges**: Real-time indicators for Twitch Chat connection, Bot Active/Standby state, and Transport Fever game mod heartbeat (`gameState.json`).
- **One-Click Bot Toggle**: Turn the bot active (`!tfon`) or standby (`!tfoff`).
- **Purchases Toggle**: Pause or resume in-game company claims, lines, towns, and vehicle purchases (`!pause all` / `!resume all`).
- **1-Click Twitch Re-authorization**: Launch browser OAuth login to refresh credentials or switch accounts on the fly without restarting.
- **OBS Studio Friendly**: Add `http://localhost:4000` as a Custom Browser Dock in OBS Studio for quick management while streaming.

#### Manual OAuth Bootstrap (Optional)
If you wish to pre-authorize or re-authorize independently of running the bot:
```bash
.\tf2_client_windows.exe oauth.bootstrap
# or from source:
mix twitch.oauth.bootstrap
```

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

#### Available Packaged Commands:

- `.\tf2_client_windows.exe` → start the bot (prompts setup if unconfigured, auto-authorizes if needed)
- `.\tf2_client_windows.exe setup` → run interactive configuration wizard
- `.\tf2_client_windows.exe config` → show current configuration and token status
- `.\tf2_client_windows.exe oauth.bootstrap` → one-time manual OAuth bootstrap

Burrito maintenance commands:

- `.\tf2_client_windows.exe maintenance directory`
- `.\tf2_client_windows.exe maintenance uninstall`

## Chat commands

- `!tfon` → enable the bot in chat (mods/broadcaster only)
- `!tfoff` → disable the bot in chat (mods/broadcaster only)
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

If `TF_INTEGRATION_GAME_FILES` is unset or empty, it uses a fresh temp folder and prints the path on start.
Type `:help` in the sim for commands. Use `:play <path> [delay_ms]` to replay a script of chat lines, `:delay <ms>` to pause before the next command, and `:ratelimit off` to disable rate limiting.

## File protocol (with the game mod)

- Shared folder: `TF_INTEGRATION_GAME_FILES` when set and non-empty, otherwise `~/.transport_fever`; if no home folder is available, `<temp>/transport_fever`.
- Bot writes: `#{order_id}.lua` (Lua `return` table with `schema_version = 1`) and appends `order_id` to `requests.txt`.
- Mod writes: `#{order_id}.json` responses; the bot reads, replies in chat, then deletes the response file (and the request `.lua` on completion).
