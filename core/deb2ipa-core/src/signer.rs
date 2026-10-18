use std::path::Path;
use crate::{EngineError, Result};

/// Pseudo-sign (Rust ldid -S equivalent) every Mach-O in the assembled bundle
/// so the exported IPA opens cleanly in SideStore/AltStore/Sideloadly, which
/// apply the real Apple ID signature at install time.
/// v0: scaffold only.
pub fn pseudo_sign(_bundle_root: &Path) -> Result<()> {
    Err(EngineError::NotImplemented("signer::pseudo_sign"))
}
