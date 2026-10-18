//! C ABI surface consumed by the SwiftUI app via the bridging header.

use std::os::raw::c_char;

const VERSION_C: &[u8] = b"0.1.0-scaffold\x00";

/// Version of deb2ipa-core as a nul-terminated string (process lifetime).
#[no_mangle]
pub extern "C" fn deb2ipa_version() -> *const c_char {
    VERSION_C.as_ptr() as *const c_char
}

/// On-device analysis result codes shared with Swift.
#[repr(C)]
pub enum Deb2IpaStatus {
    Ok = 0,
    NotDeb = 1,
    UnsupportedClass = 2,
    OutOfSpace = 3,
    InternalError = 4,
}

/// v1 entry point: analyze a deb and report its payload class.
/// TODO(v1): returns an owned analysis handle (class, warnings, dependency
/// map) freed by deb2ipa_free_analysis.
#[no_mangle]
pub extern "C" fn deb2ipa_analyze(_deb_path: *const c_char) -> Deb2IpaStatus {
    // TODO(v1): parser::inspect() + classifier::classify() over the index.
    Deb2IpaStatus::NotDeb
}
