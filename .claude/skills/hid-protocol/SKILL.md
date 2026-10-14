---
name: hid-protocol
description: HID protocol constraints for steelseriesgg-rs device code. Automatically load when editing any file under src/devices/. Contains hard rules about HidReportBuilder usage, unsafe block documentation, and experimental command code labeling.
user-invocable: false
---

## Hard rules — never violate

**HID reports**: Always use `HidReportBuilder` and the typed helpers in `src/devices/hid_reports.rs`. Never construct raw byte arrays or `Vec<u8>` / `[u8; N]` literals for HID output by hand.

**Error handling**: No `.unwrap()` or `.expect()` outside `#[cfg(test)]` blocks. Use `?` or return `Err(...)`.

**Unsafe**: Every `unsafe` block must have an inline comment explaining the specific safety invariant it relies on.

## Command code status

See `.claude/rules/experimental-protocol.md` (the single source). Any new protocol work must be labeled with its verification status; never present experimental code as confirmed.

## Pre-edit checklist

Before modifying any file in `src/devices/`:
1. `rg 'SymbolOrType' src/devices/` — locate the symbol first, read only what's needed
2. Check whether the change touches any of the command codes above
3. After editing, verify no raw byte slices were introduced
