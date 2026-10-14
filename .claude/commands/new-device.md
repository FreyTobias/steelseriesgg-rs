---
description: Scaffold a new SteelSeries device — creates the implementation file and wires it into the registry
---

Scaffold a new device for steelseriesgg-rs. Ask the user for:
1. Device name (e.g. `Apex 5`)
2. Device type: `keyboard` or `headset`
3. USB vendor ID and product ID (hex, e.g. `0x1038`, `0x1234`)

Then create the following, using existing devices as templates:

**For a keyboard:**
- `src/devices/keyboards/<snake_case_name>.rs` — implement the `Keyboard` trait (and its `Device` supertrait)
  - Stub all methods, mark protocol work `[EXPERIMENTAL]` or `[PLACEHOLDER]`
  - Use `HidReportBuilder` for all HID output — never raw bytes
- Register in `src/devices/keyboards/mod.rs` under the VID/PID
- Add to the device table in `src/devices/discovery.rs`

**For a headset:**
- `src/devices/headsets/<snake_case_name>.rs` — implement the `Headset` trait (and its `Device` supertrait)
- Register in `src/devices/headsets/mod.rs`
- Add to `src/devices/discovery.rs`

**After creating files:**
1. Run `cargo clippy --all-targets --locked -- -D warnings` and fix any errors
2. Run `cargo fmt --all`
3. Report the files created and the VID/PID that was registered

Label all protocol implementation as `[EXPERIMENTAL]` until tested on hardware.
