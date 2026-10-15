# GameSense API: ssgg server and official GG behaviour

ssgg's server is `src/gamesense/server.rs` (request types in `src/gamesense/mod.rs`). The GG sections
below were observed against GG 111.0.0 on 2026-05-26 and are reference only.

---

## ssgg server

- **Bind**: `127.0.0.1`. Port 27301 by default: `ssgg server -p <port>`, or `[gamesense]` `port` /
  `bind_address` in `config.toml` when the daemon starts the server.
- **Discovery file**: on start, ssgg writes `{"address": "127.0.0.1:<port>"}` to `coreProps.json`:
  Linux `/tmp/steelseries-engine/coreProps.json` (directory `0700`, file `0600`, owner-checked, no
  symlinks), Windows `%PROGRAMDATA%\SteelSeries\SteelSeries Engine 3\coreProps.json`, macOS
  `/Library/Application Support/SteelSeries Engine 3/coreProps.json`. On Windows this is the same file GG
  uses, so running both overwrites it.
- **CORS**: localhost-only. `is_origin_allowed` accepts origins whose host is `localhost`, `127.0.0.1` or
  `::1`, with an optional numeric port; everything else (for example `localhost.evil.com`,
  `localhost:evil.com`) is rejected. Allowed methods: GET, POST, OPTIONS; allowed header: Content-Type.
  This policy may only be tightened (`AGENTS.md`, hard constraint 3).

### Endpoints

| Method | Path | Handler | Effect |
|--------|------|---------|--------|
| POST | `/game_metadata` | `register_game` | Stores the game |
| POST | `/bind_game_event` | `bind_event` | Stores the event binding and its handlers |
| POST | `/register_game_event` | `bind_event` | Same handler as `/bind_game_event` |
| POST | `/game_event` | `game_event` | Stores the value and runs the bound handlers |
| POST | `/game_heartbeat` | `heartbeat` | Logs only |
| POST | `/remove_game` | `remove_game` | Drops the game, its bindings and values |
| POST | `/remove_game_event` | `remove_event` | Drops one binding |
| GET | `/` | `server_info` | `{"address": "127.0.0.1", "encrypted_address": null, "sse_address": null, "version": "4.0.0"}` |

Every POST returns `{"success": true}` on success. Keyboard and `rgb-per-key-zones` handlers compute a
colour (static, gradient or range) and pass it to the RGB callback; screen and tactile handlers are
logged only.

---

## Official GG (observed)

### Port discovery

GG does not use a fixed port. It publishes its addresses in
`C:\ProgramData\SteelSeries\SteelSeries Engine 3\coreProps.json` (also under
`C:\ProgramData\SteelSeries\GG\`):

```json
{"encryptedAddress":"127.0.0.1:53723","ggEncryptedAddress":"127.0.0.1:6327","address":"127.0.0.1:53714"}
```

- `address`: plain HTTP GameSense endpoint
- `encryptedAddress`: HTTPS endpoint (certificate chain unknown)
- `ggEncryptedAddress`: GG-internal endpoint

The official SDK documentation names port 27301, which is ssgg's default.

### Responses

GG echoes each request inside a wrapper object named after the endpoint and adds fields ssgg's types do
not have:

| Endpoint | GG response |
|----------|-------------|
| `/game_metadata` | `{"game_metadata": {..., "is": "", "deinitialize_timer_length_ms": 0, "enabled": false, "options": null}}` |
| `/bind_game_event`, `/register_game_event` | `{"<endpoint>": {..., "icon_id": 0, "value_optional": false, "data_fields": null}}` |
| `/game_event` | `{"game_event": {"level": "", "game": ..., "event": ..., "data": {...}}}` |
| `/game_heartbeat` | `{"game_heartbeat": {"game": ...}}` |
| `/remove_game` | `{"remove_game_event": {"game": ...}}` (key is `remove_game_event`, not `remove_game`) |

`/remove_game_event` was not tested separately. Sending `product_id` in `/bind_game_event` returns
HTTP 400; GG sets that column internally.

### CORS

GG answers with `Access-Control-Allow-Origin: *`, so any web page can call the local API. ssgg does not
copy this.

---

## Differences that could matter to clients

| Behaviour | ssgg | GG |
|-----------|------|----|
| Port | Fixed per run (default 27301) | Dynamic, from `coreProps.json` |
| POST response body | `{"success": true}` | Echo wrapper per endpoint (above) |
| `/` info endpoint | Yes | Not checked |
| CORS | Localhost only | Wildcard |
