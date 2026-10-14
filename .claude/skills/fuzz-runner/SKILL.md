---
name: fuzz-runner
description: Run the protocol fuzzer (`ssgg fuzz`) against a connected keyboard with safety guardrails, capture responses, and fold results back into docs/development/ notes.
user-invocable: true
disable-model-invocation: true
---

Run `src/devices/fuzz.rs` (`Commands::Fuzz` in `src/cli.rs`, hidden from `--help`) against real hardware. This sends arbitrary command bytes to a physical device — it can brick it or cause unexpected behavior. Only run this when the user explicitly asks to fuzz a device.

## Before running

1. Confirm a real keyboard is attached: `ssgg devices` and confirm the user is aware this targets that specific device.
2. Ask the user to confirm the command byte range — do not default to the full `0x00..0xFF` sweep unless they ask for it. Narrower ranges (e.g. probing around a known command like `0x2D` ActuationControl) are safer and faster to interpret.
3. Check battery/USB power is stable — fuzzing mid-firmware-update or on a device with a shaky connection risks a bad flash state.

## Running

```
cargo run --bin ssgg -- fuzz --start <hex> --end <hex> --delay <ms>
```

- `--delay` defaults to 100ms between commands; don't lower it without reason — faster sweeps give firmware less time to recover between probes.
- The tool prints `Sent`/`Failed` per command and `Received Response` when the device replies. Capture full stdout — the response pattern (which commands ACK vs. time out) is the actual research signal.

## After running

1. Summarize which command bytes produced a response vs. silent timeout vs. explicit failure.
2. If a command's behavior suggests a match to one of the known experimental/placeholder codes (`0x23`, `0x40`, `0x2D` — see `.claude/rules/experimental-protocol.md`), note that as a hypothesis, not a confirmation — promoting a code from experimental to confirmed requires the process in that rule file (device model + date in the commit).
3. If asked to record findings, append to `docs/development/` (check existing files there for the format other reverse-engineering notes use) rather than creating a new top-level doc.

## Never

- Never run this against a device the user hasn't explicitly named.
- Never loop the full byte range repeatedly "to be sure" — each sweep is wear on unknown firmware paths.
- Never present a fuzzing result as a confirmed protocol command in code or docs.
