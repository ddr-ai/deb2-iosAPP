//! deb2ipa-core: on-device .deb -> .ipa conversion engine for the Deb2IPA iOS app.
//!
//! Pipeline (each stage lives in its own module):
//! 1. parser        — deb (ar) parsing, control fields, data.tar entry index
//! 2. classifier    — payload classification (app / cli / tweak / daemon / ELF)
//! 3. planner       — user-reviewed conversion plan
//! 4. bundle        — Payload/<Bundle>.app assembly from deb relocation table
//! 5. macho         — load-command surgery (relocate dylibs to @rpath)
//! 6. plist_doctor  — Info.plist repair/synthesis
//! 7. signer        — pseudo-signing (ldid -S equivalent) for sideload hand-off
//! 8. validator     — pre-flight gates; no IPA is exported unless all pass
//! 9. report        — conversion report surfaced in the UI
//!
//! ffi exposes the small C ABI the SwiftUI layer consumes.

pub mod bundle;
pub mod classifier;
pub mod ffi;
pub mod macho;
pub mod parser;
pub mod planner;
pub mod plist_doctor;
pub mod report;
pub mod signer;
pub mod validator;

pub const VERSION: &str = "0.1.0";

/// Errors that can abort a conversion stage.
#[derive(Debug, thiserror::Error)]
pub enum EngineError {
    #[error("stage not implemented yet: {0}")]
    NotImplemented(&'static str),
    #[error("stage failed: {0}")]
    Failed(String),
}

pub type Result<T> = std::result::Result<T, EngineError>;
