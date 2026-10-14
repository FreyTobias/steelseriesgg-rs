# Handoff: Apex Pro TKL 2023 (PID 0x1628) protocol work

Written 2026-10-14. Read this first, then `docs/development/apex-pro-tkl-2023-gg-capture.md` (the protocol
write-up) and `CLAUDE.md` / `.claude/rules/experimental-protocol.md` (labelling rules).

A new session does not inherit the old prompt cache; this file plus the note above carry the context.

## Goal

Reverse engineer the official SteelSeries GG (Windows) protocol from a USB capture and implement it in this
project. Standing permission from the user: install any missing tools without asking.

## State

- Branch `main`, up to date with `origin/main`. Nothing committed from this work.
- Uncommitted changes:
  - `src/devices/keyboards/apex_pro_tkl_2023.rs`: `0x1628` now uses the direct path (packet ID 0x40),
    GG's 84-key table `WIRED_2023_KEYS`, a 645-byte buffer (1 report-ID + 644 wire bytes), and skips the
    0x4B init. Gen3 models keep `TKL_KEYS` (112) and 643. Tests: `wired_2023_uses_the_gg_captured_layout`,
    `wired_2023_key_table_has_no_duplicates`, `gen3_keeps_the_112_key_table` (replaced the old
    `wired_2023_keeps_its_own_path`).
  - `src/devices/keyboards/mod.rs`: Unix `send_feature` uses `info.path` (control interface 1) for
    `APEX_PRO_TKL_2023`; other models still look up hidraw interface 3.
  - `src/main.rs`: `warn_if_gg_engine_running()` (Windows, `sysinfo`, looks for `SteelSeriesEngine.exe`),
    called at the start of `cmd_rgb`.
  - `docs/development/apex-pro-tkl-2023-gg-capture.md`: new, the protocol note.
- Verified: `cargo fmt`, `cargo clippy --all-targets --locked -- -D warnings` clean, `cargo test --locked`
  127 passed / 3 ignored. Hardware: `ssgg rgb color FF0000` turned the keyboard solid red (user-confirmed,
  GG stopped); USBPcap showed `wValue 0x0300, wIndex 1, wLength 644, 40 54 04 ff 00 00 05 ...`.
- Not tested: other colours, per-key patterns, Linux hidraw path, `ssgg actuation` while GG runs.
- All `[EXPERIMENTAL]` labels are still in place. Per the rules, removal needs a commit naming the device
  model and date; the user has not asked for that.

## Key findings (details in the note)

- GG layout: Electron UI (`app.asar`) only talks to the local core. HID code is in
  `C:\Program Files\SteelSeries\GG\apps\engine`: `SteelSeriesEngine.exe` (Go) -> `SSEdevice.dll` ->
  `HIDDLL.dll`. `deviceSpecifications\*.edevice` are encrypted; not decrypted (no key extraction attempted).
- Transport on this wired model: HID SET_REPORT to USB interface 1. Feature report ID 0, 644 bytes, for
  lighting and profile upload. Output report ID 0, 64 bytes, for commands. Replies on EP 0x82.
- Lighting: `0x40`, count (`0x54`), then `[usage][R][G][B]` x84, zero padded. GG streams ~19 fps and
  overwrites other programs while its engine runs. With GG closed the keyboard keeps the last frame.
- Profile: 12,500 bytes in 25 chunks, header `03 01 80 | len u16 LE (500) | offset u16 LE | 00 00`.
  Offsets for key W: actuation 1100, second threshold 1170, mode 1462 (0 off / 2 Rapid Trigger /
  3 Key Guard), Rapid Tap 2700. Key A is at +13. Actuation raw values: 0.1mm=05, 1.0=15, 2.0=39, 3.0=86.
- 64-byte commands: poll set `02 01 80`, `b1`, `b2`, `34`, `90` (90 returns firmware `1.19.7`);
  `38 66 01/00` seen with Rapid Tap; `38 67 0a 00 04 07 <n> ...` seen in an earlier uncontrolled run.
- Brightness 0 in GG is software: lighting frames become all-black RGB.

## Open items

1. Profile checksum at blob offset 12320..12323 is unsolved. 10 common CRC32 polynomials with all
   init/xor/reflection combos, Adler-32 and a byte sum were tried over ranges starting 0/1/2/4/9 and ending
   12320/12324/12500. Do not write the profile blob until solved. Lighting needs no checksum.
2. ~~Full key-to-offset map.~~ Done: 70-slot per-key tables at 1084 (actuation), 1154 (reset), 1446
   (release mode), 1516 (RT sensitivity); slot map in the note and in `WIRED_2023_PROFILE_SLOTS` /
   `profile_slot()` (`apex_pro_tkl_2023.rs`, 3 new tests). Source: `run3.pcap` plus GG's engine DB.
3. GG's init sequence (capture must start before GG launches). `0x4B` is unverified for this model.
4. Meaning of `b1`, `b2`, `34`, `38 66`, `38 67`.
5. The extra `00 09 00..` output report sent by the existing `initialize()` path before each frame.
   Existing code comments say 0x09 makes the controller fall back to its stored profile. Not investigated.
6. Brightness 50 looked identical to 100 on the wire; unresolved.
7. The `experimental-apex-2023` feature path (`Apex2023DirectCommand`, sent through `send_raw` padded to 65
   bytes as an output write) does not match what GG does; not touched.
8. Decide whether to commit, and whether to drop `[EXPERIMENTAL]` for the lighting frame.

## Environment facts

- Windows 11, PowerShell. Rust build via `rtk cargo ...`; binary `.\target\debug\ssgg.exe`.
- Installed this session via winget: Wireshark 4.6.9 (`C:\Program Files\Wireshark\tshark.exe`), USBPcap 1.5.4.0
  (`C:\Program Files\USBPcap\USBPcapCMD.exe`). Driver works after the reboot; the only hub is `\\.\USBPcap1`.
  `USBPcapCMD` with no arguments is interactive and hangs: always pass `-d \\.\USBPcap1 -o <file> -A`.
- The keyboard is USB device address 3 in the captures (re-check with tshark if the port changes).
- Stopping GG: kill every `SteelSeries*` process (the engine respawns otherwise). Restart GG with
  `SteelSeriesGGEZ.exe -dataPath="C:\ProgramData\SteelSeries\GG" -dbEnv=production` from
  `C:\Program Files\SteelSeries\GG`. `SteelSeriesGG.exe` alone exits with code 2. GG is currently running.
- A GUI helper must not be launched with `-WindowStyle Hidden` (it hid the form).
- tshark fields that worked: `-e frame.time_epoch -e usb.data_fragment`, filters
  `usb.setup.bRequest==9 && usb.bmRequestType==0x21 && usb.setup.wValue==0x0300|0x0200`.
- `ctx_execute_file` refuses paths outside the project; run analysis scripts with `python -I <script> <args>`.

## Persistent artifacts (outside the repo)

`C:\Users\Ven0m0\gg-capture-artifacts\`:
`run2.pcap` (controlled 18-step capture, 117 MB), `steps.csv` (step name and epoch per step),
`blobs.bin` (13 reassembled 12,500-byte profile blobs, one per cycle), `r2_feat.txt` / `r2_out.txt` /
`r2_in82.txt` (extracted reports with epoch), analysis scripts `an4.py an5.py an8.py an9.py crc2.py`, and
`guided_capture.ps1` (the always-on-top step prompter that logs timestamps).
The first, uncontrolled capture (`run1.pcap`, 284 MB) was not kept.
Key-map capture: `keymap_capture.ps1` (prompter, 8 s steps, each step sets one more key to 3.0 mm),
`run3.pcap` (82 MB), `steps3.csv` (epoch written with a German decimal comma, so the column splits
wrongly; per-cycle order in `blobs3.bin` is what identified the keys), `blobs3.bin` (19 blobs, more
samples for the checksum), `an10.py` (reassembles blobs and prints changed slots per step).

Step order in `steps.csv`: idle, W actuation 0.1 / 1.0 / 2.0 / 3.0 / 1.0, W Rapid Trigger on/off,
W Rapid Tap on/off, W Key Guard on/off, A actuation 2.0 / 1.0, brightness 0 / 100 / 50, idle (15 s each).

## Suggested next steps

1. Review and commit the three code files plus the note (message should name Apex Pro TKL 2023, PID 0x1628,
   date 2026-10-14, and say lighting was hardware-tested once).
2. Test more lighting on hardware with GG closed: other colours, `ssgg rgb perkey ...`, `ssgg rgb off`.
3. Solve the checksum (try the Go side: strings and constants near profile code in `SteelSeriesEngine.exe`,
   or capture more single-bit edits to fit the function), then consider writing profile settings.
4. Capture GG startup to get the init sequence.
