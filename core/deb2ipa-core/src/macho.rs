use crate::classifier::SUBSTRATE_SYMBOLS;
use goblin::Object;

#[derive(Debug, Clone, Default)]
pub struct BinaryScan {
    pub macho: bool,
    pub elf: bool,
    pub architectures: Vec<String>,
    pub linked_libraries: Vec<String>,
    pub rpaths: Vec<String>,
    pub substrate_symbols: bool,
}

fn contains_bytes(haystack: &[u8], needle: &[u8]) -> bool {
    if needle.is_empty() || haystack.len() < needle.len() {
        return false;
    }
    haystack.windows(needle.len()).any(|w| w == needle)
}

/// Scan file bytes: Mach-O vs ELF, architectures, load commands, and any
/// Substrate symbols that would make the package un-runnable on stock iOS.
pub fn scan(bytes: &[u8]) -> Option<BinaryScan> {
    let obj = Object::parse(bytes).ok()?;
    match obj {
        Object::Mach(mach) => {
            let mut scan = BinaryScan { macho: true, ..Default::default() };
            for arch in mach.iter_arches().flatten() {
                scan.architectures.push(format!("{:?}", arch.cputype));
            }
            for (_, exe) in mach.iter_exes() {
                scan.linked_libraries.extend(exe.libs.iter().map(|l| l.to_string()));
                scan.rpaths.extend(exe.rpaths.iter().map(|r| r.to_string()));
            }
            for sym in SUBSTRATE_SYMBOLS {
                // v0: naive byte scan; v1 walks symbol tables.
                if contains_bytes(bytes, sym.as_bytes()) {
                    scan.substrate_symbols = true;
                    break;
                }
            }
            Some(scan)
        }
        Object::Elf(elf) => Some(BinaryScan {
            elf: true,
            architectures: vec![format!("{:?}", elf.header.e_machine)],
            linked_libraries: elf.libraries.iter().map(|l| l.to_string()).collect(),
            ..Default::default()
        }),
        _ => None,
    }
}

#[derive(Debug, Clone)]
pub struct LoadCommandRewrite {
    pub old: String,
    pub new: String,
}

/// Rewrite LC_LOAD_DYLIB / LC_ID_DYLIB entries per the relocation map so every
/// bundled dependency resolves inside the app sandbox (at @rpath).
/// v0: scaffold only. The v1 implementation edits load commands in place via
/// goblin, preserving __TEXT page alignment.
pub fn rewrite_load_commands(_map: &[LoadCommandRewrite]) -> crate::Result<()> {
    Err(crate::EngineError::NotImplemented("macho::rewrite_load_commands"))
}

/// Ensure LC_RPATH contains @executable_path/Frameworks and
/// @loader_path/Frameworks on the main executable.
pub fn set_rpaths(_binary: &mut [u8]) -> crate::Result<()> {
    Err(crate::EngineError::NotImplemented("macho::set_rpaths"))
}
