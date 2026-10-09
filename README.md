# Transport Fever Twitch Client

Twitch chatbot for a Transport Fever Twitch integration mod.

It connects to Twitch chat via Twitch IRC, writes request files for the game mod to process, and replies in chat when the mod completes actions.

> [!IMPORTANT]
> **Windows users: install the Visual C++ runtime before launching the client.**
> The bundled executable requires the [Microsoft Visual C++ Redistributable (x64)](https://aka.ms/vc14/vc_redist.x64.exe). If Windows shows `VCRUNTIME140.dll was not found`, install this package, then launch the client again.
> Windows 10 build 1511 or newer is required. You do not need Elixir or Erlang installed.

Standalone executables are available for **Windows**, **Linux**, and **macOS**. No runtime dependencies or programming environments are required.

## Setup

### 1. Zero-Config Twitch Login (Default)

The bot comes pre-configured with default credentials for seamless 1-click browser authorization. **You do not need to register a Twitch Developer application.**

When running the bot for the first time, press Enter to choose **Browser authentication (recommended)**, enter your Twitch username, then press Enter to use the same account for the bot. The bot will automatically open your web browser, ask you to log in with Twitch, and connect immediately!

*(Advanced / Custom Application)*: If you prefer to manage your own Twitch Developer application rather than the default credentials, you can register one at `https://dev.twitch.tv/console/apps` (OAuth Redirect URL: `http://localhost:4000/oauth/callback`) and configure custom `client_id` and `client_secret` settings. See [DEVELOPMENT.md](./DEVELOPMENT.md) for more details.

### 2. Configuration

The client supports three ways to configure settings (evaluated in order of precedence):
1. **Environment variables** (highest priority, great for Docker/headless environments)
2. **`config.json` file** (checked in `./config.json` or `~/.config/transport_fever/config.json`)
3. **Interactive Setup Wizard** (prompts you on first launch if unconfigured)

#### Quick Setup via Interactive Wizard
On first launch, including double-clicking the bundled Windows executable, the bot starts setup automatically when the channel or bot username is missing. After saving your settings, it continues to Twitch browser authorization if needed. Later launches reuse your settings. Before connecting to chat, the bot validates the token and checks that it belongs to the configured bot username and grants chat access. Rejected saved credentials trigger browser authorization again; temporary validation failures keep saved credentials and report an error. Invalid manually supplied tokens must be updated through setup.

The wizard offers two paths:

- **Browser authentication (default):** only your Twitch username is required. You can optionally use a separate bot account; sign in as that account when Twitch opens. No Client ID, Client Secret, or token entry is needed. Selecting this path replaces manual credentials with the built-in application defaults.
- **Manual configuration (advanced):** configure your own Client ID and optional Client Secret, or supply an existing OAuth IRC token. Press Enter to retain existing values or skip optional fields. Without an IRC token, browser authorization is used when needed.

Running the standalone `setup` command saves settings and exits. Start the executable normally afterward to connect and authorize if needed.

If setup is cancelled, input is unavailable, or the configuration cannot be read, startup stops with an error. Open a terminal and run the setup command below, or provide a valid configuration file. Automatic setup is skipped in tests, IEx, and when the bot is explicitly disabled.

You can also run setup manually at any time:

```bash
# On Windows:
.\tf_client.exe setup

# On Linux or macOS:
./tf_client setup
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

```bash
# On Windows:
.\tf_client.exe config

# On Linux / macOS:
./tf_client config
```

#### Environment variables (optional overrides)

- `TWITCH_BOT_USER`: bot Twitch username (lowercase recommended)
- `TWITCH_BOT_OAUTH` (optional): bot OAuth token for IRC (must start with `oauth:`); if unset, uses the stored OAuth tokens
- `TWITCH_CHANNELS`: comma/space separated list of channels to join (no `#`)
- `TWITCH_CLIENT_ID` (optional): your own Twitch application client ID; uses the built-in application if unset
- `TWITCH_CLIENT_SECRET` (optional): secret for your own Twitch application; not needed for the default browser login
- `TWITCH_REDIRECT_URI` (optional): OAuth redirect URI (default: `http://localhost:4000/oauth/callback`)
- `TWITCH_MOD_CHANNELS` (optional): channels where the bot is a moderator (rate limits)
- `TWITCH_DEBUG` (optional): `true`/`false`
- `TF_CONFIG_PATH`: custom path to `config.json`
- `TF_INTEGRATION_GAME_FILES`: folder shared with the game mod (contains `requests_<save_uuid>.txt`, `gameState.json`, and response files). If unset or empty, the bot uses `~/.transport_fever`, matching the game mod.
- `TF_ENABLE_TWITCH_BOT`: set to `false` to disable starting the bot
- `TF_DISABLE_RATE_LIMITS`: set to `true` to disable rate limiting
- `TF_REQUEST_QUEUE_DELAYS_MS` (optional): per-request delays (e.g. `TOWN=5000,COMPANY=0,LINE=0,VEHICLE=0`). Requests with `0` delay are sent immediately; delayed types are queued FIFO.

### 3. Run & Auto-Authorization

Start the game with the mod enabled so it can create/update `gameState.json` in the shared game files folder, then run:

```bash
# On Windows:
.\tf_client.exe
# (or double-click the executable)

# On Linux or macOS:
./tf_client
```

- **Seamless Auto-Authorization**: If tokens are not present, the bot automatically opens your browser to authorize with Twitch, saves the credentials to `~/.config/transport_fever/twitch_tokens.json`, and connects to chat immediately without requiring a restart!
- By default the bot joins the configured channels but does not send any chat messages until enabled by a moderator/broadcaster with `!tfon`.

#### Streamer Control Panel (`http://localhost:4000`)

When the bot runs, it automatically serves a lightweight Streamer Control Panel at `http://localhost:4000`:
- **Game File Diagnostics**: The control panel reports missing files, filesystem errors (such as permission denied), invalid JSON, and missing save identifiers. The full path is kept off the dashboard to avoid exposing local usernames while streaming. Diagnostic details are available as `game.game_state_path`, `game.error_code`, and `game.error_message` at `/api/status`. A connected state requires valid JSON with a non-empty `save_uuid`.
- **Live Status Badges**: Real-time indicators for Twitch Chat connection, Bot Active/Standby state, and Transport Fever game mod heartbeat (`gameState.json`).
- **One-Click Bot Toggle**: Turn the bot active (`!tfon`) or standby (`!tfoff`).
- **Purchases Toggle**: Pause or resume in-game company claims, lines, towns, and vehicle purchases (`!pause all` / `!resume all`).
- **1-Click Twitch Re-authorization**: Launch browser OAuth login to refresh credentials or switch accounts on the fly without restarting.
- **OBS Studio Friendly**: Add `http://localhost:4000` as a Custom Browser Dock in OBS Studio for quick management while streaming.

#### Manual OAuth Bootstrap (Optional)
If you wish to pre-authorize or re-authorize independently of running the bot:

```bash
# On Windows:
.\tf_client.exe oauth.bootstrap

# On Linux / macOS:
./tf_client oauth.bootstrap
```

### Available Executable Commands

- `<executable>` → start the bot (prompts setup if unconfigured, auto-authorizes if needed)
- `<executable> setup` → run interactive configuration wizard
- `<executable> config` → show current configuration and token status
- `<executable> oauth.bootstrap` → one-time manual OAuth bootstrap

*(Replace `<executable>` with `.\tf_client.exe` or `./tf_client` depending on your platform.)*

## Chat commands

- `!tfon` → enable the bot in chat (mods/broadcaster only)
- `!tfoff` → disable the bot in chat (mods/broadcaster only)
- `!pause <claim|town|line|vehicle|all>` → pause a redemption type (mods/broadcaster only)
- `!resume <claim|town|line|vehicle|all>` → resume a redemption type (mods/broadcaster only)
- `!paused` → list paused redemption types (mods/broadcaster only)
- `!towncreation <on|off>` → enable/disable automatic town creation (mods/broadcaster only)
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

## Game Mod Integration

The client communicates with the Transport Fever game mod through a shared folder:

- **Shared folder location:** `~/.transport_fever` by default, or the folder specified in the `TF_INTEGRATION_GAME_FILES` environment variable.
- The game mod exports live game state (`gameState.json`) to this folder.
- When chat commands arrive, the client writes request orders to this folder, and the game mod executes them in-game and outputs results for the bot to reply in chat.
- Make sure both the game mod and the client are running simultaneously and pointing to the same folder.

## Development

If you want to work with the source code, run tests, use the local chat simulator, build executables, or inspect the internal mod IPC file protocol, please see the [Development Guide](./DEVELOPMENT.md).
