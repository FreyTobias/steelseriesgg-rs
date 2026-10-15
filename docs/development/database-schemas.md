# GG Database Schemas

Three SQLite databases used by GG, read on 2026-05-26 unless noted. All are locked while GG runs: stop
GG and open read-only, or copy first. Field meanings for the Apex Pro TKL 2023 per-key settings were
re-checked against controlled USB captures on 2026-10-14; where they differ, the capture note
[apex-pro-tkl-2023-gg-capture.md](apex-pro-tkl-2023-gg-capture.md) wins.

| Database | Path | Size | Purpose |
|----------|------|------|--------|
| Engine | `GG\apps\engine\db\database.db` | ~44 MB | Device registry, profiles, actuation, OLED |
| Prism | `GG\apps\engine\prism\db\database.db` | ~2.7 MB | RGB lighting configs and key layout |
| Sonar | `GG\apps\sonar\db\database.db` | ~2.7 MB | Audio DSP, EQ, mic processing |

All paths are under `C:\ProgramData\SteelSeries\`.

---

## Engine Database

Source: device with Apex Pro TKL 2023 (PID 0x1628, engine `devices.id` = 242), 2026-05-26.

### `devices` — device model registry

```sql
CREATE TABLE "devices" (
    id                     INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE,
    product_id             INTEGER NOT NULL,   -- (VID << 16) | PID
    name                   TEXT NOT NULL UNIQUE,
    full_name              TEXT NOT NULL,
    type                   INTEGER NOT NULL,
    settings               TEXT NOT NULL DEFAULT '{}',        -- JSON, current deployed state
    undeployedsettings     TEXT NOT NULL DEFAULT '{}',
    model_type_id          INT NOT NULL DEFAULT 0,
    hidden                 INT NOT NULL DEFAULT 0,
    global_device_settings TEXT NOT NULL DEFAULT ''
)
```

**`product_id` encoding**: `(VID << 16) | PID` — same as the GG firmware folder names.
Apex Pro TKL 2023: `product_id = 272111144` = `0x10381628` → VID=0x1038, PID=0x1628.
This is a 32-bit composite, not the 16-bit USB PID.

**`type` values**:

| Value | Device type |
|-------|-------------|
| 0 | keyboard |
| 1 | mouse |
| 3 | headset |
| 4 | gamepad |
| 5 | misc (Tobii, USB hub) |
| 6 | virtual/software |
| 7 | mousepad |
| 8 | motherboard |
| 10 | laptop keyboard (MSI) |
| 11 | speakers |
| 12 | microphone |

### `devices.settings` JSON

The `settings` column holds the currently-deployed device state as JSON. Top-level keys for the Apex Pro TKL 2023:

| Key | Type | Description |
|-----|------|-------------|
| `name` | `{characters: [u8; 24]}` | Device label as ASCII bytes, null-padded |
| `region` | `{region_id: i32}` | Layout region (-1 = US default) |
| `meta_toggle_hid` | `{no_live_deploy: 1, code: 240}` | FN key HID code |
| `mappings` | `{no_live_deploy: 1, button_mappings: {buttons: [...]}}` | Per-key function remaps |
| `hall_thresholds` | `{keys: [{hid, l, h}]}` | Per-key actuation (`h`) and reset (`l`) points |
| `second_actuation_thresholds` | `{keys: [{hid, l, h}]}` | Meaning unknown |
| `oled_display` | `{data: [u8; 1024]}` | 128×64 1-bpp bitmap, row-major |
| `apex_2022_oled_display_sequence` | object | OLED animation sequence |

#### `hall_thresholds`

```json
{"keys": [{"hid": 4, "l": 46, "h": 50}, ...]}
```

- `hid`: USB HID usage ID (4 = A, 240 = FN)
- `h`: actuation point, `l`: reset point, both raw sensor values
- The scale is non-linear. Known actuation points: 0.1 mm = 5, 1.0 mm = 21, 2.0 mm = 57, 3.0 mm = 134;
  GG's default is `h` 21 / `l` 18 (capture note). A linear "25 units per mm" reading is wrong.

#### `second_actuation_thresholds`

Same `{hid, l, h}` structure as `hall_thresholds`. All zero in the 2026-10-14 config; where it lands in
the on-board profile is unknown. It is not the Rapid Trigger switch (that is `release_mode`).

#### `mappings.button_mappings.buttons[]`

```json
{"hid_code": 4, "function": 81, "key_codes": [4, 0, 0, 0]}
```

- `function: 81` = passthrough (standard keypress)
- Other function values = macro/media/custom action

#### `oled_display.data`

1024 bytes = 128×64 pixels at 1 bpp, row-major. All-zeros = blank. Default = SteelSeries logo.

---

### `configurations` — named profiles

```sql
CREATE TABLE configurations (
    id                   UUID PRIMARY KEY UNIQUE,
    device_id            INTEGER NOT NULL,   -- references devices.id
    name                 TEXT,               -- "Default", "Gaming", "Fortnite", etc.
    settings             TEXT,               -- JSON, same structure as devices.settings
    active               INTEGER DEFAULT 0,  -- 1 = currently active
    user_id              INTEGER NOT NULL,
    mutable              INTEGER DEFAULT 1,
    last_deployed        INTEGER DEFAULT 0,
    undeployedsettings   TEXT DEFAULT '{}',
    cloud_last_updated_at TEXT DEFAULT '',
    is_deleted           INTEGER DEFAULT 0,
    sync_config          INTEGER DEFAULT 0
)
```

Observed profiles for Apex Pro TKL 2023 (`device_id=242`): Default, Gaming (active), main, Config 4, Config 1 2, Fortnite.

#### Rapid trigger fields (configurations only)

| Key | Type | Description |
|-----|------|-------------|
| `rapid_tap_enable` | `{enabled: 0\|1}` | Global Rapid Tap on/off |
| `rapid_tap_pairs` | object | Rapid Tap key pairs (HID usages; default A, D) |
| `rapid_trigger_sensitivity` | `{keys: [{hid, sensitivity}]}` | Per-key Rapid Trigger sensitivity (default 2; scale unknown) |
| `release_mode` | `{keys: [{hid, mode}]}` | Per-key release mode |

**`release_mode.mode`** (from the 2026-10-14 captures): `0` = off, `2` = Rapid Trigger, `3` = Key Guard.
Mode `4` was seen on HID 40, 42, 43, 44, 57, 226, 227, 230, 231, 240 in a 2026-05 "Gaming" config; its
meaning is unknown.

---

### How GG applies these settings

GG does not send per-setting HID commands. After every change it rewrites the whole 12,500-byte on-board
profile, which holds per-key tables for actuation, reset, release mode and Rapid Trigger sensitivity.
Offsets, slot map and the unsolved checksum are in the capture note. ssgg's `0x2D` actuation command is
`[EXPERIMENTAL]` and is not what GG sends.

---

### Other notable tables

| Table | Content |
|-------|--------|
| `physical_devices` | Connected hardware (populated only when device is plugged in) |
| `wireless_device_information` | TX dongle PID → RX headset PID mappings |
| `game_integration_games` | Known games by name |
| `game_integration_registered_events` | Per-game events (e.g. "HEALTH", "AMMO") |
| `game_integration_event_bindings` | Event → key binding (GameSense config) |
| `macros` | Recorded macro sequences |
| `sub_apps` | Registered GG sub-app records |
| `loadout_presets` | Multi-device loadout configurations |

---

## Prism Database (RGB)

Source: `GG\apps\engine\prism\db\database.db`, device_id=242, 2026-05-26.

### `configs` — RGB lighting configurations

```sql
CREATE TABLE configs (
    id                        TEXT    PRIMARY KEY,
    is_deleted                INTEGER NOT NULL DEFAULT 0,
    is_hidden_immutable       INTEGER NOT NULL DEFAULT 0,
    is_current                INTEGER NOT NULL DEFAULT 0,
    is_last_manually_deployed INTEGER NOT NULL DEFAULT 0,
    name                      TEXT    NOT NULL DEFAULT '',
    config_json               TEXT    NOT NULL DEFAULT '',
    schema                    INTEGER NOT NULL DEFAULT 0,
    is_per_device             INTEGER NOT NULL DEFAULT 0
)
```

- `config_json`: full RGB state for all three lighting modes (base/idle/reactive)
- `schema=4`: user or preset-based configs; `schema=0`: immutable built-in default
- `is_per_device=1`: config targets a specific device (via `config_per_device` join table)
- Active config: `is_current=1`

### `zone_cache` — per-key address table

```sql
CREATE TABLE zone_cache (
    device_id       INTEGER NOT NULL,
    unique_id       TEXT    NOT NULL,   -- 64-bit int as TEXT; matches zoneIds in config_json
    x               INTEGER NOT NULL,   -- bitmap x coordinate
    y               INTEGER NOT NULL,   -- bitmap y coordinate
    hid_code        INTEGER NOT NULL,   -- USB HID Usage ID (page 7, keyboard/keypad)
    actuation_level INTEGER NOT NULL DEFAULT 0,
    linear_index    INTEGER,
    PRIMARY KEY (device_id, unique_id)
)
```

`unique_id` values in this table are the same integers used in `config_json.zoneIds` — this is the bridge between layout data and RGB config.

**`actuation_level`**: values seen for device 242 are `0` (23 keys: Esc, F-row, navigation cluster,
arrows) and `600` (61 analog keys). It is a key class, not an actuation depth; per-key actuation lives
in the engine DB `hall_thresholds`. The 23 `0` keys are the ones with no slot in the on-board profile.

### Config JSON structure

```json
{
  "base": {
    "globalConfig": {
      "graphics": [
        {
          "type": 0,
          "zIndex": 0,
          "foreground": {
            "duration": 4690,
            "spatialWavelength": 64,
            "gradient": {
              "colors": [
                {"color": {"red": 255, "green": 0,   "blue": 255}, "position": 0},
                {"color": {"red": 255, "green": 234, "blue": 0},   "position": 85},
                {"color": {"red": 0,   "green": 204, "blue": 255}, "position": 170}
              ]
            }
          },
          "metadata": {"effectType": "COLOR_SHIFT"}
        }
      ],
      "defaultColor": {"red": 0, "green": 0, "blue": 0}
    },
    "deviceConfigs": [
      {
        "deviceId": 242,
        "zoneIds": ["68117837727006720", "..."],
        "config": {
          "defaultColor": {"red": 255, "green": 0, "blue": 255},
          "metadata": {"effectType": "SINGLE_COLOR"}
        }
      }
    ]
  },
  "idle": { ... },
  "idleTimeMs": 0,
  "reactive": { ... }
}
```

**Effect types**:
- `COLOR_SHIFT` — animated gradient cycle (`duration`, `spatialWavelength`, `gradient`)
- `SINGLE_COLOR` — static color (`defaultColor`)
- `BLOOM` — reactive per-key ripple (requires bitmap coordinates)

**Three lighting states**:

| State | When active |
|-------|------------|
| `base` | Normal use |
| `idle` | After `idleTimeMs` ms of inactivity |
| `reactive` | Key-press overlay on top of base/idle |

ssgg has no idle or reactive lighting state.

### Complete zone map — Apex Pro TKL 2023

84 keys total (US layout). `al` = actuation_level.

**Function row** (y=256, al=0):

| unique_id | x | hid | key |
|-----------|---|-----|-----|
| 68117545676177408 | 140 | 41 | Escape |
| 68117854913822720 | 212 | 58 | F1 |
| 68118005237678080 | 247 | 59 | F2 |
| 68118159856500736 | 283 | 60 | F3 |
| 68118314475323392 | 319 | 61 | F4 |
| 68118464799178752 | 354 | 62 | F5 |
| 68118619418001408 | 390 | 63 | F6 |
| 68118774036824064 | 426 | 64 | F7 |
| 68118924360679424 | 461 | 65 | F8 |
| 68119078979502080 | 497 | 66 | F9 |
| 68119229303357440 | 532 | 67 | F10 |
| 68119383922180096 | 568 | 68 | F11 |
| 68119538541002752 | 604 | 69 | F12 |

**Number row** (y=212):

| unique_id | x | hid | key | al |
|-----------|---|-----|-----|----|
| 68117545673293824 | 140 | 53 | \` ~ | 600 |
| 68117700292116480 | 176 | 30 | 1 ! | 600 |
| 68117854910939136 | 212 | 31 | 2 @ | 600 |
| 68118005234794496 | 247 | 32 | 3 # | 600 |
| 68118159853617152 | 283 | 33 | 4 $ | 600 |
| 68118314472439808 | 319 | 34 | 5 % | 600 |
| 68118464796295168 | 354 | 35 | 6 ^ | 600 |
| 68118619415117824 | 390 | 36 | 7 & | 600 |
| 68118774033940480 | 426 | 37 | 8 * | 600 |
| 68118924357795840 | 461 | 38 | 9 ( | 600 |
| 68119078976618496 | 497 | 39 | 0 ) | 600 |
| 68119229300473856 | 532 | 45 | - _ | 600 |
| 68119383919296512 | 568 | 46 | = + | 600 |
| 68119620142497792 | 623 | 42 | Backspace | 600 |
| 68119907905306624 | 690 | 73 | Insert | 0 |
| 68120058229161984 | 725 | 74 | Home | 0 |
| 68120212847984640 | 761 | 75 | Page Up | 0 |

**Tab / QWERTY top row** (y=181):

| unique_id | x | hid | key | al |
|-----------|---|-----|-----|----|
| 68117584325967872 | 149 | 43 | Tab | 600 |
| 68117777599496192 | 194 | 20 | Q | 600 |
| 68117932218318848 | 230 | 26 | W | 600 |
| 68118082542174208 | 265 | 8 | E | 600 |
| 68118237160996864 | 301 | 21 | R | 600 |
| 68118391779819520 | 337 | 23 | T | 600 |
| 68118542103674880 | 372 | 28 | Y | 600 |
| 68118696722497536 | 408 | 24 | U | 600 |
| 68118851341320192 | 444 | 12 | I | 600 |
| 68119001665175552 | 479 | 18 | O | 600 |
| 68119156283998208 | 515 | 19 | P | 600 |
| 68119310902820864 | 551 | 47 | [ { | 600 |
| 68119461226676224 | 586 | 48 | ] } | 600 |
| 68119615845498880 | 622 | 49 | \ \| | 600 |
| 68119817708961792 | 669 | 76 | Delete | 0 |
| 68119972327784448 | 705 | 77 | End | 0 |
| 68120122651639808 | 740 | 78 | Page Down | 0 |

**Home row** (y=150):

| unique_id | x | hid | key | al |
|-----------|---|-----|-----|----|
| 68117614388707328 | 156 | 57 | Caps Lock | 600 |
| 68117837727006720 | 208 | 4 | A | 600 |
| 68117992345829376 | 244 | 22 | S | 600 |
| 68118142669684736 | 279 | 7 | D | 600 |
| 68118297288507392 | 315 | 9 | F | 600 |
| 68118451907330048 | 351 | 10 | G | 600 |
| 68118602231185408 | 386 | 11 | H | 600 |
| 68118756850008064 | 422 | 13 | J | 600 |
| 68118911468830720 | 458 | 14 | K | 600 |
| 68119061792686080 | 493 | 15 | L | 600 |
| 68119216411508736 | 529 | 51 | ; : | 600 |
| 68119366735364096 | 564 | 52 | ' " | 600 |
| 68119615843467264 | 622 | 40 | Enter | 600 |

**ZXCV row** (y=120):

| unique_id | x | hid | key | al |
|-----------|---|-----|-----|----|
| 68117678811250688 | 171 | 225 | L Shift | 600 |
| 68117962279092224 | 237 | 29 | Z | 600 |
| 68118116897914880 | 273 | 27 | X | 600 |
| 68118267221770240 | 308 | 6 | C | 600 |
| 68118421840592896 | 344 | 25 | V | 600 |
| 68118576459415552 | 380 | 5 | B | 600 |
| 68118726783270912 | 415 | 17 | N | 600 |
| 68118881402093568 | 451 | 16 | M | 600 |
| 68119036020916224 | 487 | 54 | , < | 600 |
| 68119186344771584 | 522 | 55 | . > | 600 |
| 68119340963594240 | 558 | 56 | / ? | 600 |
| 68119624431435776 | 624 | 229 | R Shift | 600 |
| 68120114057707520 | 738 | 82 | Up Arrow | 0 |

**Bottom row** (y=89):

| unique_id | x | hid | key | al |
|-----------|---|-----|-----|----|
| 68117575730003968 | 147 | 224 | L Ctrl | 600 |
| 68117794773336064 | 198 | 227 | L GUI (Win) | 600 |
| 68117988046864384 | 243 | 226 | L Alt | 600 |
| 68118464788234240 | 354 | 44 | Space | 600 |
| 68118954414505984 | 468 | 230 | R Alt | 600 |
| 68119147688034304 | 513 | 231 | R GUI (Win) | 600 |
| 68119336666595328 | 557 | 240 | FN | 600 |
| 68119521350189056 | 600 | 228 | R Ctrl | 600 |
| 68119748983455744 | 653 | 80 | Left Arrow | 0 |
| 68119903602278400 | 689 | 81 | Down Arrow | 0 |
| 68120058221101056 | 725 | 79 | Right Arrow | 0 |

**Summary**: 84 keys, 61 analog (al=600) and 23 non-analog (al=0).

**Notes**:
- HID 240 (FN key) has no standard USB HID usage. SteelSeries assigns 0xF0 as a synthetic ID.
- PrintScreen, ScrollLock and Pause have no key of their own.
- `unique_id` values encode (x, y) bitmap position as 64-bit integers; decoding is unnecessary for ssgg since `hid_code` identifies keys directly.

---

## Sonar Database (Audio)

Source: `GG\apps\sonar\db\database.db`, 2026-05-26.
Status: partial. Volume routing is not stored in this DB.

### Tables

```sql
CREATE TABLE configs (
    id               TEXT     NOT NULL UNIQUE PRIMARY KEY,
    name             TEXT     NOT NULL,
    vad              INTEGER  NOT NULL,
    data             TEXT     NOT NULL,        -- JSON DSP config
    schema_version   INTEGER  NOT NULL,
    created_at       DATETIME NOT NULL,
    updated_at       DATETIME NOT NULL,
    is_preset        INTEGER  NOT NULL,        -- 0=user, 1=built-in
    default_data     TEXT     NOT NULL,
    game_ids         TEXT     NOT NULL DEFAULT '',  -- game names that auto-activate this config
    ...
)

CREATE TABLE selected_config (
    vad       INTEGER NOT NULL UNIQUE,
    config_id TEXT    NOT NULL UNIQUE
)

CREATE TABLE key_value (
    key        TEXT     NOT NULL PRIMARY KEY,
    value      TEXT     NOT NULL,
    ...
)
```

**`vad` values** (Virtual Audio Device):

| Value | Channel |
|-------|--------|
| 1 | Game output (speakers/headphones) |
| 2 | Microphone input |
| 3 | Media output (music player) |
| 4 | Aux / chat render (incoming chat) |
| 5 | Chat capture / streaming mic |

**`key_value` known keys**: `ONBOARDING_FINISHED`, `HEART_BEAT`, `MODE` ("Classic"), `GAME_FALLBACK_DEVICES`, `STREAM_MODE_*`, `STREAMING_STREAM_MODE_*`.

### Output config JSON (vad=1)

```json
{
  "bassBoostState":    {"enabled": true, "value": 0},
  "trebleBoostState":  {"enabled": true, "value": 0},
  "voiceClarityState": {"enabled": true, "value": 0},
  "smartVolume":       {"enabled": false, "volumeLevel": 0, "loudness": "balanced"},
  "generalGain": 0,
  "parametricEQ": {
    "enabled": true,
    "filter1":  {"enabled": true,  "qFactor": 0.7071, "frequency": 35,    "gain": 0, "type": "peakingEQ"},
    "filter2":  {"enabled": true,  "qFactor": 0.7071, "frequency": 120,   "gain": 0, "type": "peakingEQ"},
    "filter3":  {"enabled": true,  "qFactor": 0.7071, "frequency": 1000,  "gain": 0, "type": "peakingEQ"},
    "filter4":  {"enabled": true,  "qFactor": 0.7071, "frequency": 6000,  "gain": 0, "type": "peakingEQ"},
    "filter5":  {"enabled": true,  "qFactor": 0.7071, "frequency": 18000, "gain": 0, "type": "peakingEQ"},
    "filter6":  {"enabled": false, "qFactor": 0.7071, "frequency": 1000,  "gain": 0, "type": "peakingEQ"},
    "filter7":  {"enabled": false, "qFactor": 0.7071, "frequency": 2000,  "gain": 0, "type": "peakingEQ"},
    "filter8":  {"enabled": false, "qFactor": 0.7071, "frequency": 4000,  "gain": 0, "type": "peakingEQ"},
    "filter9":  {"enabled": false, "qFactor": 0.7071, "frequency": 8000,  "gain": 0, "type": "peakingEQ"},
    "filter10": {"enabled": false, "qFactor": 0.7071, "frequency": 16000, "gain": 0, "type": "peakingEQ"}
  },
  "virtualSurroundState": false,
  "virtualSurroundChannels": {
    "frontLeft":  {"position": 30,   "gain": 0},
    "frontRight": {"position": -30,  "gain": 0},
    "center":     {"position": 0,    "gain": 0},
    "subWoofer":  {"position": 0,    "gain": 0},
    "rearLeft":   {"position": 150,  "gain": 0},
    "rearRight":  {"position": -150, "gain": 0},
    "sideLeft":   {"position": 90,   "gain": 0},
    "sideRight":  {"position": -90,  "gain": 0}
  },
  "formFactor": "headphones",
  "globalEnableState": true
}
```

**EQ filter types**: `"peakingEQ"`, `"lowShelving"`, `"highShelving"` (biquad).
Filters 1–5 enabled by default; 6–10 off.

### Mic config JSON (vad=2)

```json
{
  "noiseReductionState":        {"enabled": false, "value": 0.0},
  "volumeStabilizerState":      {"enabled": false, "value": 0.0},
  "noiseGateState":             {"enabled": false, "value": -60.0},
  "automaticNoiseGateState":    {"enabled": false, "value": 0.0},
  "impactNoiseReductionState":  {"enabled": false, "value": 0.0},
  "noiseCancelingState":        {"enabled": false, "value": 0.9},
  "acousticEchoCancelingState": false,
  "globalEnableState": true,
  "parametricEQ": {
    "enabled": true,
    "filter1":  {"enabled": true, "qFactor": 0.7071, "frequency": 31.0,    "gain": 0.0, "type": "lowShelving"},
    "filter2":  {"enabled": true, "qFactor": 0.7071, "frequency": 62.0,    "gain": 0.0, "type": "peakingEQ"},
    "filter3":  {"enabled": true, "qFactor": 0.7071, "frequency": 125.0,   "gain": 0.0, "type": "peakingEQ"},
    "filter4":  {"enabled": true, "qFactor": 0.7071, "frequency": 250.0,   "gain": 0.0, "type": "peakingEQ"},
    "filter5":  {"enabled": true, "qFactor": 0.7071, "frequency": 500.0,   "gain": 0.0, "type": "peakingEQ"},
    "filter6":  {"enabled": true, "qFactor": 0.7071, "frequency": 1000.0,  "gain": 0.0, "type": "peakingEQ"},
    "filter7":  {"enabled": true, "qFactor": 0.7071, "frequency": 2000.0,  "gain": 0.0, "type": "peakingEQ"},
    "filter8":  {"enabled": true, "qFactor": 0.7071, "frequency": 4000.0,  "gain": 0.0, "type": "peakingEQ"},
    "filter9":  {"enabled": true, "qFactor": 0.7071, "frequency": 8000.0,  "gain": 0.0, "type": "peakingEQ"},
    "filter10": {"enabled": true, "qFactor": 0.7071, "frequency": 16000.0, "gain": 0.0, "type": "highShelving"}
  }
}
```

### Built-in presets (`is_preset=1`, vad=1)

Valorant Pro, CS:GO Pro, Apex Legends, COD Warzone, Fortnite Pro, League of Legends, FPS Footsteps.
Each carries game-specific EQ tuning in its `data` JSON.

### Relation to ssgg

ssgg does not read this database. `SonarClient` (`src/audio/sonar.rs`, feature `sonar`) talks to Sonar's
local HTTP API: configs (list, select), channel volume and mute, chat mix, classic/streamer mode and
stream redirections. EQ and mic DSP parameters are not implemented.

### Shared config links (issue #277, researched 2026-10-15)

Sonar's "share preset" produces a web link that carries only a pointer, not the EQ data:

- Link: `https://www.steelseries.com/deeplink/gg/sonar/config/v1/import?url=<base64>` (format from a SteelSeries
  employee's LinkedIn post; not found in the local GG install).
- `url=` is plain base64 of a CDN URL, e.g. `https://community-configs.steelseriescdn.com/v1/<uuid>` (decoded).
- An unauthenticated GET on that URL returned the config JSON (HTTP 200):
  `{"data":{"data":{...},"schemaVersion":5,"virtualAudioDevice":"game"},"metadata":{"name":..,"author":..}}`.
  `data.data` has the same shape as the `configs.data` column above: `parametricEQ.enabled` plus `filter1`..`filter10`,
  each `{enabled, frequency (Hz), gain (dB), qFactor, type}`; `type` seen as `peakingEQ`, `lowShelving`,
  `highShelving`.
- GG registers the `ssgg://` URL scheme (`HKCU\Software\Classes\ssgg` -> `SteelSeriesGGClient.exe "%1"`); the
  renderer imports through Sonar's local `GET <configs>/retrieveFromUrlHash?hash=<hash>` (strings in `app.asar`).

Unknown, so no import code yet: the exact `ssgg://` form, whether `hash` is the base64 `url=` value, the body Sonar
accepts to create a config (`POST /configs`?), `schemaVersion` compatibility, the full filter `type` list, and the
CDN's terms of use. Sources: https://github.com/wex/sonar-rev (`openapi/swagger.json`),
https://www.linkedin.com/pulse/steelseries-sonar-now-supports-sharing-peq-settings-kevin-lin.
