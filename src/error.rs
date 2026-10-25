//! Error types for the SteelSeries GG library.

use thiserror::Error;

/// Result type alias using our Error type.
pub type Result<T> = std::result::Result<T, Error>;

/// Main error type for SteelSeries GG operations.
#[derive(Debug, Error)]
pub enum Error {
    /// HID API initialization or communication error
    #[error("HID error: {0}")]
    Hid(#[from] hidapi::HidError),

    /// Device not found
    #[error("Device not found: {0}")]
    DeviceNotFound(String),

    /// Device communication error
    #[error("Device communication error: {0}")]
    DeviceCommunication(String),

    /// Invalid device configuration
    #[error("Invalid configuration: {0}")]
    InvalidConfig(String),

    /// Profile error
    #[error("Profile error: {0}")]
    Profile(String),

    /// IO error
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    /// Serialization error
    #[error("Serialization error: {0}")]
    Serialization(#[from] serde_json::Error),

    /// Serialization message error
    #[error("Serialization error: {0}")]
    SerializationMessage(String),

    /// File system error
    #[error("File system error: {0}")]
    FileSystemError(String),

    /// TOML parsing error
    #[error("Config parse error: {0}")]
    TomlParse(#[from] toml::de::Error),

    /// GameSense server error
    #[error("GameSense error: {0}")]
    GameSense(String),

    /// Audio system error
    #[error("Audio error: {0}")]
    Audio(String),

    /// Permission denied (requires root/sudo)
    #[error("Permission denied: {0}")]
    PermissionDenied(String),

    /// Unsupported device
    #[error("Unsupported device: vendor={vendor_id:#06x}, product={product_id:#06x}")]
    UnsupportedDevice { vendor_id: u16, product_id: u16 },

    /// Tracing initialization error
    #[error("Logging initialization error: {0}")]
    Tracing(#[from] tracing::subscriber::SetGlobalDefaultError),

    /// Generic error
    #[error("{0}")]
    Other(String),
}

impl From<String> for Error {
    fn from(s: String) -> Self {
        Error::Other(s)
    }
}

impl From<&str> for Error {
    fn from(s: &str) -> Self {
        Error::Other(s.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unsupported_device_prints_both_ids_as_four_digit_hex() {
        let err = Error::UnsupportedDevice {
            vendor_id: 0x1038,
            product_id: 0x0a,
        };
        assert_eq!(err.to_string(), "Unsupported device: vendor=0x1038, product=0x000a");
    }

    #[test]
    fn string_conversions_become_other_and_print_unprefixed() {
        assert_eq!(Error::from("boom").to_string(), "boom");
        assert_eq!(Error::from(String::from("bang")).to_string(), "bang");
    }

    #[test]
    fn io_errors_convert_with_the_question_mark_operator() {
        fn fails() -> Result<()> {
            Err(std::io::Error::new(std::io::ErrorKind::NotFound, "gone"))?
        }
        let err = fails().unwrap_err();
        assert!(matches!(err, Error::Io(_)));
        assert_eq!(err.to_string(), "IO error: gone");
    }
}
