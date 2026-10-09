# Development Guide

This guide contains instructions for working with the source code of **Transport Fever Twitch Client**, running tests, using developer tooling, building standalone releases, and understanding the internal game mod file protocol.

## Prerequisites

- **Elixir & Erlang/OTP**: Elixir `~> 1.19` and compatible Erlang/OTP.
- **Packaging Requirements** (only needed for building Burrito standalone executables):
  - `zig` 0.15.2
  - `xz`
  - `7z` or `7zz` (for Windows targets)

## Setting Up the Project

Clone the repository and install the dependencies:

```bash
# Fetch Elixir dependencies
mix deps.get

# Compile the project
mix compile
```

## Running from Source

You can run the client directly from source using Mix:

```bash
# Run in the foreground:
mix run --no-halt

# Or start an interactive IEx shell:
iex -S mix
```

### Developer Mix Tasks

The client provides several Mix tasks for development, testing, and configuration:

| Command | Description |
| :--- | :--- |
| `mix tf2.setup` | Runs the interactive configuration wizard in your terminal. |
| `mix tf2.config` | Displays current configuration and credential status. |
| `mix twitch.oauth.bootstrap` | Runs the standalone one-time Twitch browser OAuth flow. |
| `mix tf.sim` | Launches the interactive chat simulator without connecting to Twitch. |


## Custom Twitch Application Setup (Optional)

By default, the client uses pre-configured application credentials for 1-click browser login. If you prefer to manage your own Twitch Developer application during development:

1. Register an application at the [Twitch Developer Console](https://dev.twitch.tv/console/apps).
2. Set the **OAuth Redirect URL** to: `http://localhost:4000/oauth/callback`
3. Configure your custom credentials via environment variables (`TWITCH_CLIENT_ID` and `TWITCH_CLIENT_SECRET`) or in `config.json`.

## Testing & Code Quality

Always verify your changes before submitting PRs or cutting releases:

```bash
# Run the test suite:
mix test

# Run the complete verification suite (formatting, credo, and tests):
mix check
```

### Formatting & Linting

```bash
# Check code formatting:
mix format --check-formatted

# Format code:
mix format

# Run Credo:
mix credo --strict
```


## Local Simulator (No Twitch)

Run an interactive shell that simulates viewer chat messages and prints bot replies without connecting to Twitch:

```bash
mix tf.sim
```

- If `TF_INTEGRATION_GAME_FILES` is unset or empty, the simulator uses a fresh temporary directory and prints its path on start.
- Simulate viewer chat commands using the syntax `username: !command`:
  ```text
  alice: !claim My Company
  alice: !town My Company
  alice: !profit
  bob: !claim
  ```

### Simulator Commands

- `:help` - Show simulator help and available commands.
- `:play <path> [delay_ms]` - Replay a script of chat lines with optional delay.
- `:delay <ms>` - Pause execution before the next command.
- `:ratelimit off` - Disable rate limiting during the simulation session.


## Building Standalone Executables (Burrito)

[Burrito](https://github.com/burrito-elixir/burrito) is configured to build self-contained, single-file executables for Windows, Linux, and macOS without requiring Elixir or Erlang installed on the target machine.

### Targets

Release targets configured in `mix.exs`:

| Target Name | Platform | Output Binary |
| :--- | :--- | :--- |
| `windows` | Windows x86_64 | `burrito_out/tf2_client_windows.exe` |
| `linux` | Linux x86_64 | `burrito_out/tf2_client_linux` |
| `macos` | macOS Intel x86_64 | `burrito_out/tf2_client_macos` |
| `macos_silicon` | macOS Apple Silicon aarch64 | `burrito_out/tf2_client_macos_silicon` |


### Build Commands

Build releases from Linux, macOS, or Windows through WSL:

```bash
# Build Windows executable:
MIX_ENV=prod BURRITO_TARGET=windows mix release

# Build Linux executable:
MIX_ENV=prod BURRITO_TARGET=linux mix release

# Build macOS (Intel) executable:
MIX_ENV=prod BURRITO_TARGET=macos mix release

# Build macOS (Apple Silicon) executable:
MIX_ENV=prod BURRITO_TARGET=macos_silicon mix release

# Build all executables at once:
MIX_ENV=prod mix release
```

### Burrito Cache & Maintenance

Burrito production binaries unpack their embedded release on first launch and reuse that unpacked payload for subsequent runs of the same app version.

- If you rebuild with code changes but keep the same `version` in `mix.exs`, the executable may keep running the previously unpacked code.
- **For normal releases:** Bump the project version in `mix.exs` before building.
- **For local verification of a same-version rebuild:** Clear the cached payload:
  ```bash
  # Windows:
  .\burrito_out\tf2_client_windows.exe maintenance uninstall

  # Linux:
  ./burrito_out/tf2_client_linux maintenance uninstall
  ```
- Inspect the unpacked runtime path:
  ```bash
  # Windows:
  .\burrito_out\tf2_client_windows.exe maintenance directory

  # Linux:
  ./burrito_out/tf2_client_linux maintenance directory
  ```


## File Protocol & Game Mod Architecture

The client communicates asynchronously with the Transport Fever game mod through file-based inter-process communication:

1. **Shared Folder:**
   - Specified via `TF_INTEGRATION_GAME_FILES` when set and non-empty.
   - Defaults to `~/.transport_fever` (or `<temp>/transport_fever` if home is unavailable).
2. **Game State Export:**
   - The game mod exports metadata and world state to `gameState.json`.
   - The client polls `gameState.json` for save identification (`save_uuid`), mod heartbeat, and company finances.
3. **Request Lifecycle:**
   - The bot writes `#{order_id}.lua` (Lua `return` table with `schema_version = 1`).
   - The bot appends `order_id` to `requests_<save_uuid>.txt`.
4. **Response Lifecycle:**
   - The mod reads pending requests, applies mutations, and writes `#{order_id}.json` response files.
   - The bot reads `#{order_id}.json`, replies to chat, and deletes the response file (as well as the request `#{order_id}.lua` on completion).
5. **Per-Save Request Indexes:**
   - Each game save has an independent request index (`requests_<save_uuid>.txt`).
   - Loading another save leaves its pending requests intact; returning to that save resumes them.
   - The client removes an index entry after consuming a terminal response (success or permanent failure), while pending responses retain the entry.
   - Queue replacement is atomic and serialized with submissions within the client.
   - Both the mod and client must be updated together.
   - Inactive save queues are retained with no automatic expiration.
6. **Startup Recovery:**
   - On client startup, existing per-save indexes are recovered for cleanup.
   - Terminal responses for those recovered requests are removed without replying chat messages (the original channel routing is not persisted).
   - Pending requests remain queued.
