//! Runs the built `ssgg` binary for the paths that need no hardware.

use std::process::Command;

fn ssgg(args: &[&str]) -> std::process::Output {
    Command::new(env!("CARGO_BIN_EXE_ssgg"))
        .args(args)
        .output()
        .expect("spawn ssgg")
}

#[test]
fn version_prints_the_package_version() {
    let out = ssgg(&["--version"]);
    assert!(out.status.success());
    assert!(String::from_utf8_lossy(&out.stdout).contains(env!("CARGO_PKG_VERSION")));
}

#[test]
fn help_succeeds_and_lists_core_subcommands() {
    let out = ssgg(&["--help"]);
    assert!(out.status.success());
    let text = String::from_utf8_lossy(&out.stdout);
    for sub in ["rgb", "profile", "headset", "mouse"] {
        assert!(text.contains(sub), "--help should list `{sub}`");
    }
}

#[test]
fn an_unknown_subcommand_is_a_usage_error_not_a_panic() {
    let out = ssgg(&["definitely-not-a-command"]);
    assert_eq!(out.status.code(), Some(2), "clap usage errors exit with 2");
}
