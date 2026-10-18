use crate::parser::DataEntry;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PayloadClass {
    /// Standalone GUI app under /Applications — fully convertible.
    StandaloneApp,
    /// Command-line tool — convertible via the Console wrapper template.
    CliTool,
    /// Substrate/ElleKit hook — cannot run on stock iOS.
    SubstrateTweak,
    /// launchd daemon — wrapper only, no background execution.
    Daemon,
    /// Linux ELF binary — cannot run natively on iOS.
    LinuxElf,
    /// More than one class present — plan resolves per component.
    Mixed,
    Unknown,
}

impl PayloadClass {
    pub fn convertible(&self) -> bool {
        matches!(self, PayloadClass::StandaloneApp | PayloadClass::CliTool | PayloadClass::Mixed)
    }
}

/// Heuristic classification from the data.tar entry list.
/// NOTE(v0): content-level Mach-O/ELF scanning happens during extraction in v1;
/// install-path prefixes are the reliable first signal.
pub fn classify(entries: &[DataEntry]) -> PayloadClass {
    let has = |prefix: &str| entries.iter().any(|e| e.path.starts_with(prefix));
    let mut classes: Vec<PayloadClass> = Vec::new();
    if has("/Library/MobileSubstrate/") {
        classes.push(PayloadClass::SubstrateTweak);
    }
    if has("/Applications/") {
        classes.push(PayloadClass::StandaloneApp);
    }
    if has("/Library/LaunchDaemons/") || has("/Library/LaunchAgents/") {
        classes.push(PayloadClass::Daemon);
    }
    if has("/usr/bin/") || has("/usr/sbin/") {
        classes.push(PayloadClass::CliTool);
    }
    match classes.len() {
        0 => PayloadClass::Unknown,
        1 => classes[0],
        _ => PayloadClass::Mixed,
    }
}

/// Symbols that betray a Substrate tweak even outside the
/// MobileSubstrate directory.
pub const SUBSTRATE_SYMBOLS: &[&str] = &[
    "MSHookFunction",
    "MSHookMessageEx",
    "MSHookMemory",
];
