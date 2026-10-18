use std::path::{Path, PathBuf};
use crate::{EngineError, Result};

/// Deb install path -> .app bundle path mapping used during assembly.
#[derive(Debug, Clone)]
pub struct Relocation {
    pub deb_path: &'static str,
    pub bundle_path: &'static str,
}

pub fn relocation_table() -> Vec<Relocation> {
    vec![
        Relocation { deb_path: "/usr/lib", bundle_path: "Frameworks" },
        Relocation { deb_path: "/usr/libexec", bundle_path: "Frameworks" },
        Relocation { deb_path: "/Library/Frameworks", bundle_path: "Frameworks" },
        Relocation { deb_path: "/usr/share", bundle_path: "Resources/share" },
        Relocation { deb_path: "/etc", bundle_path: "Resources/etc" },
        Relocation { deb_path: "/var/mobile", bundle_path: "Resources/var-mobile" },
    ]
}

/// Assemble Payload/<Bundle>.app in the workspace from extracted deb files:
/// normalizes permissions, records symlink maps, and applies relocations.
/// v0: scaffold only.
pub fn assemble(_plan: &crate::planner::ConversionPlan, _workspace: &Path) -> Result<PathBuf> {
    Err(EngineError::NotImplemented("bundle::assemble"))
}
