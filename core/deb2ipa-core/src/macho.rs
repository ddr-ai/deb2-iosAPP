use crate::classifier::SUBSTRATE_SYMBOLS;
use goblin::Object;
use goblin::mach::Mach;

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

/// Human-readable name for a goblin cputype value.
fn cpu_name(cputype: u32) -> String {
    match cputype {
        0x0100000C => "arm64".to_string(),
        0x0100000F => "arm64e".to_string(),
        0x0000000C => "arm".to_string(),
        0x01000007 => "x86_64".to_string(),
        0x00000007 => "x86".to_string(),
        other => format!("cpu-{other:x}"),
    }
}

/// Scan file bytes: Mach-O vs ELF, architectures, load commands, and any
/// Substrate symbols that would make the package un-runnable on stock iOS.
pub fn scan(bytes: &[u8]) -> Option<BinaryScan> {
    let obj = Object::parse(bytes).ok()?;
    match obj {
        Object::Mach(mach) => {
            let mut scan = BinaryScan { macho: true, ..Default::default() };
            match mach {
                Mach::Binary(exe) => {
                    scan.architectures.push(cpu_name(exe.header.cputype));
                    scan.linked_libraries.extend(exe.libs.iter().map(|l| l.to_string()));
                    scan.rpaths.extend(exe.rpaths.iter().map(|r| r.to_string()));
                }
                Mach::Fat(multi) => {
                    for arch in multi.iter_arches().flatten() {
                        scan.architectures.push(cpu_name(arch.cputype()));
                    }
                    // TODO(v1): descend per slice and collect each MachO's
                    // libs/rpaths for the dependency graph.
                }
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
