use std::path::Path;
use crate::{EngineError, Result};

/// Pre-flight gates that mirror what iOS checks at install + launch time.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Gate {
    /// Payload/ + exactly one .app, no symlink loops, no absolute symlinks.
    Structure,
    /// Required Info.plist keys present and well-formed.
    InfoPlist,
    /// Every Mach-O in the bundle carries a (pseudo) signature.
    Signature,
    /// Every LC_LOAD_DYLIB resolves inside the bundle or to an allow-listed
    /// system dylib for the target iOS version.
    LoadCommands,
    /// No bundled scripts/configs write outside the app container.
    Sandbox,
}

impl Gate {
    pub fn all() -> [Gate; 5] {
        [Gate::Structure, Gate::InfoPlist, Gate::Signature, Gate::LoadCommands, Gate::Sandbox]
    }
}

#[derive(Debug, Clone)]
pub struct GateResult {
    pub gate: Gate,
    pub passed: bool,
    pub details: Vec<String>,
}

/// Run all pre-flight gates over the assembled bundle.
/// v0: scaffold only — the pipeline refuses to export an IPA unless every
/// gate passes.
pub fn preflight(_bundle_root: &Path) -> Result<Vec<GateResult>> {
    Err(EngineError::NotImplemented("validator::preflight"))
}
