# TF2Client

Twitch chatbot for a Transport Fever 2 Twitch integration mod.

It connects to Twitch chat via `tmi`, writes request `.lua` files for the game mod to process, and polls `*.json` response files to reply in chat.

## Setup

### Environment variables

- `TWITCH_BOT_USER`: bot Twitch username (lowercase recommended)
- `TWITCH_BOT_OAUTH`: bot OAuth token (must start with `oauth:`)
- `TWITCH_CHANNELS`: comma/space separated list of channels to join (no `#`)
- `TWITCH_MOD_CHANNELS` (optional): channels where the bot is a moderator (rate limits)
- `TWITCH_DEBUG` (optional): `true`/`false`
- `TF2_INTEGRATION_GAME_FILES`: folder shared with the game mod (contains `requests.txt`, `gameState.json`, and response files)
- `TF2_ENABLE_TWITCH_BOT` (optional): set to `false` to disable starting the bot

### Run

Start the game with the mod enabled so it can create/update `gameState.json` in `TF2_INTEGRATION_GAME_FILES`, then run:

`iex -S mix`

## Chat commands

- `!claim [company name]` → create/claim company
- `!town [company name]` → purchase/assign a town
- `!line <carrier> <cargo>` → purchase/assign a transport line
- `!vehicle <carrier> <cargo>` → purchase/assign a vehicle
- `!profit` → show your total profit
- `!vehicles` → show how many vehicles you own
- `!carriers` → list valid carrier types
- `!cargo` → list valid cargo types
- `!help` → show help

Valid carriers: `AIR`, `RAIL`, `ROAD`, `WATER`, `TRAM`.

## Local simulator (no Twitch)

Run an interactive shell that simulates chat messages and prints bot replies:

`mix tf2.sim`

If `TF2_INTEGRATION_GAME_FILES` is not set, it uses a fresh temp folder and prints the path on start.

## File protocol (with the game mod)

- Bot writes: `#{order_id}.lua` (Lua `return` table with `schema_version = 1`) and appends `order_id` to `requests.txt`.
- Mod writes: `#{order_id}.json` responses; the bot reads, replies in chat, then deletes the response file (and the request `.lua` on completion).
