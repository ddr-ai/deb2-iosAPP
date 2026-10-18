use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum SigningProfile {
    /// Pseudo-signed IPA handed to SideStore/AltStore/Sideloadly for real signing.
    AdHocHandoff,
    /// User supplies p12 + mobileprovision (v2).
    DeveloperIdentity,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum IconSource {
    FromPayload,
    UserProvided,
    Placeholder,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlanOptions {
    pub bundle_id: String,
    pub display_name: String,
    pub version: String,
    pub icon: IconSource,
    pub profile: SigningProfile,
    pub min_ios_version: String,
}

#[derive(Debug, Clone)]
pub struct ConversionPlan {
    pub options: PlanOptions,
    pub relocations: Vec<crate::bundle::Relocation>,
    pub warnings: Vec<crate::report::ConversionWarning>,
}

/// Build a default bundle id from the deb Package field.
pub fn default_bundle_id(package: &str, prefix: &str) -> String {
    let sanitized: String = package
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() || c == '.' { c } else { '-' })
        .collect();
    if sanitized.is_empty() {
        format!("{prefix}.converted")
    } else {
        format!("{prefix}.{sanitized}")
    }
}

/// Apple marketing versions are dotted numeric triples (x.y.z).
/// Debian epochs ("2:1.0~rc1") and revisions are stripped first.
pub fn sanitize_version(raw: &str) -> String {
    // Drop the epoch: everything before the last ':' is packaging metadata.
    let raw = raw.rsplit(':').next().unwrap_or(raw);
    // Keep only the leading dotted-numeric run; drop debian suffixes
    // ("~rc1", "-4", "+deb12") entirely.
    let numeric: String = raw
        .chars()
        .take_while(|c| c.is_ascii_digit() || *c == '.')
        .collect();
    let mut nums: Vec<String> = numeric
        .split('.')
        .filter(|s| !s.is_empty())
        .map(|s| s.chars().take(3).collect())
        .take(3)
        .collect();
    while nums.len() < 3 {
        nums.push("0".to_string());
    }
    nums.join(".")
}

/// Draft the conversion plan from analysis + user options.
/// v0: returns the plan skeleton; dependency analysis lands in v1.
pub fn draft(options: PlanOptions) -> ConversionPlan {
    ConversionPlan {
        options,
        relocations: crate::bundle::relocation_table(),
        warnings: Vec::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sanitizes_versions() {
        assert_eq!(sanitize_version("1.2.3-4"), "1.2.3");
        assert_eq!(sanitize_version("2:1.0~rc1"), "1.0.0");
        assert_eq!(sanitize_version("abc"), "0.0.0");
    }

    #[test]
    fn builds_bundle_ids() {
        assert_eq!(default_bundle_id("demo.app", "com.ddrai"), "com.ddrai.demo.app");
        assert_eq!(default_bundle_id("wget+weird", "com.ddrai"), "com.ddrai.wget-weird");
    }
}
