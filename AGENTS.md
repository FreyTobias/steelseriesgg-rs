# steelseriesgg-rs — Agent Handbook

## Project context

Open-source SteelSeries GG replacement for Linux. Controls SteelSeries keyboards and headsets via USB HID: RGB lighting effects, a GameSense-compatible HTTP server (port 27301), device profiles, and optional PulseAudio/PipeWire mixer and Sonar integration.

- **Language**: Rust 2024 edition (MSRV and toolchain: see Source-of-truth files)
- **Primary binary**: `ssgg` (`src/main.rs`, clap CLI)
- **Library crate**: `steelseries_gg` (`src/lib.rs`)
- **Platform**: Linux-first; Windows build supported but not primary
- **Config**: `$XDG_CONFIG_HOME/ssgg/config.toml`
- **Repo**: `https://github.com/Ven0m0/steelseriesgg-rs`

---

## Quick orientation

Use `rg --files src/` for the full tree. Non-obvious entry points:

```
src/main.rs                    main() and most cmd_* handlers
src/cli.rs                     clap types (Cli, Commands, *Action) and argument parse helpers
src/daemon.rs                  daemon loop, hot-plug monitoring, GameSense startup
src/error.rs                   crate::error::Error (thiserror) + Result alias
src/devices/hid_reports.rs     HidReportBuilder and typed HID commands - use this, not raw bytes
src/devices/discovery.rs       DeviceManager: enumeration, hot-plug, fingerprinting
src/devices/keyboards/         Keyboard impls (apex.rs, apex_pro_tkl_2023.rs = experimental)
src/gamesense/server.rs        Axum HTTP server (port 27301)
src/audio/                     feature `audio` (pulse.rs) and `sonar` (sonar.rs)
src/bin/                       helper binaries, not part of `ssgg` (discover_actuation probes actuation firmware)
assets/                        udev rules, systemd user unit
tests/                         integration tests
docs/development/              historical reverse-engineering notes
```

---

## Source-of-truth files

When prose docs and code disagree, always trust these files. Do not quote toolchain, MSRV, or pinned dependency versions from memory or from this document; read them.

| File | What it controls |
|------|-----------------|
| `Cargo.toml` | dependency versions and pins, features, MSRV, edition |
| `rust-toolchain.toml` | toolchain channel and components |
| `.github/workflows/ci.yml` | exact CI commands, pinned CI toolchain, feature matrix |
| `src/devices/hid_reports.rs` | HID command codes and report layouts |

---

## Toolchain and CI

### Local commands

Run the smallest relevant subset for any given change.

| Step | Command |
|------|---------|
| Format check | `cargo fmt --all -- --check` |
| Lint | `cargo clippy --all-targets --locked -- -D warnings` |
| Test | `cargo test --locked` |
| Release build | `cargo build --release --locked` |

Add `--features <flag>` when touching feature-gated code. The CI feature matrix is in
`.github/workflows/ci.yml`; the `ci-matrix` skill runs it locally. The `audio` feature needs `libpulse-dev` on
Debian/Ubuntu.

---

## Feature flags

| Flag | Enables | Extra dep |
|------|---------|-----------|
| *(none)* | Core RGB, GameSense, profiles | — |
| `audio` | AudioMixer, PulseAudio/PipeWire backend | `libpulse-dev` |
| `sonar` | SonarClient HTTP integration | — (reqwest already in tree) |
| `experimental-apex-2023` | Apex Pro TKL 2023 direct per-key RGB | — |

`audio` and `sonar` are independent; do not couple them. `experimental-apex-2023` is behind a feature flag until validated on hardware — do not present it as production-ready.

---

## Hard constraints

1. **HID reports**: always use `HidReportBuilder` and typed helpers in `src/devices/hid_reports.rs`. Never build raw byte arrays by hand.
2. **hidapi pin**: keep the exact `=` pin on `hidapi` in `Cargo.toml`; changing it requires explicit task justification.
3. **GameSense CORS**: enforce localhost-only origin; the policy may only be tightened, never relaxed.
4. **Propagate errors**: use `?` or return an explicit `Err` value — no `unwrap` or `expect` in production paths.
5. **Error types**: `crate::error::Error` with `thiserror` at library boundaries; `anyhow` with `context()` in `src/main.rs` and binaries.
6. **Protocol accuracy**: `experimental-apex-2023` and `PerKeyRgb (0x23)` are reverse-engineered and unverified. Label new protocol work clearly; never state it as confirmed unless tested on hardware.
7. **Minimal scope**: fix what the task asks, nothing more. No opportunistic refactors.
8. **No mutable global state**, no panics in non-test code (unless explicitly fatal and documented), no ignored `Result`s.
9. **`unsafe` blocks** must document the safety invariant inline.
10. **Platform-gated deps**: Unix-only crates (`rustix`) live under `[target.'cfg(unix)'.dependencies]`; keep uses behind matching `cfg`.

---

## Rust conventions

- Naming: `snake_case` for functions and modules, `PascalCase` for types and traits, `SCREAMING_SNAKE_CASE` for constants.
- `rustfmt.toml`: edition 2024 style, max 120 columns, 4-space indentation.
- Prefer `&T` borrows over owned values when ownership is not needed.
- New dependencies require justification; avoid heavy transitive deps.
- No comments that restate what the code does — comment only non-obvious invariants or workarounds.

---

## Working rules

- **Search before reading**: `rg 'TypeName|fn_name' src/`, then read only the relevant lines. Large files: `src/main.rs`, `src/devices/hid_reports.rs`.
- **Documents**: only create planning or analysis documents when explicitly requested.

---

## Protocol research notes

- `docs/development/` is historical and may be outdated; verify against current source before acting on it.
- Command-code status (confirmed / experimental / placeholder) lives in `.claude/rules/experimental-protocol.md`.

---

## Backlog

Tracked in `PLAN.md` (prioritized) and `TODO.md` (lightweight list). Do not duplicate status here.
