use crate::parser::DebControl;
use crate::planner::PlanOptions;

pub const REQUIRED_KEYS: &[&str] = &[
    "CFBundlePackageType",
    "CFBundleExecutable",
    "CFBundleIdentifier",
    "CFBundleName",
    "CFBundleShortVersionString",
    "CFBundleVersion",
    "MinimumOSVersion",
    "UILaunchStoryboardName",
];

/// Synthesize a complete Info.plist from deb control fields + plan options.
pub fn synthesize(control: &DebControl, options: &PlanOptions) -> plist::Dictionary {
    let mut d = plist::Dictionary::new();
    d.insert("CFBundlePackageType".into(), plist::Value::from("APPL"));
    d.insert("CFBundleIdentifier".into(), plist::Value::from(options.bundle_id.clone()));
    d.insert("CFBundleDisplayName".into(), plist::Value::from(options.display_name.clone()));
    d.insert("CFBundleName".into(), plist::Value::from(options.display_name.clone()));
    d.insert("CFBundleShortVersionString".into(), plist::Value::from(options.version.clone()));
    d.insert("CFBundleVersion".into(), plist::Value::from(options.version.clone()));
    d.insert("MinimumOSVersion".into(), plist::Value::from(options.min_ios_version.clone()));
    d.insert("CFBundleInfoDictionaryVersion".into(), plist::Value::from("6.0"));
    d.insert("CFBundleExecutable".into(), plist::Value::from(control.package.clone()));
    d
}

/// Report Info.plist keys that iOS requires but the payload does not provide.
/// v1 repairs them automatically (launch screen key, executable name, ...).
pub fn missing_keys(d: &plist::Dictionary) -> Vec<&'static str> {
    REQUIRED_KEYS.iter().copied().filter(|k| !d.contains_key(*k)).collect()
}
