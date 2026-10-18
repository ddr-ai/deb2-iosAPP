use std::fs::File;
use std::io::{BufReader, Cursor as IoCursor, Read};
use std::path::Path;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum ParseError {
    #[error("not a valid Debian package: {0}")]
    InvalidDeb(String),
    #[error("unsupported compression for member '{0}'")]
    UnsupportedCompression(String),
    #[error("missing required member: {0}")]
    MissingMember(String),
    #[error(transparent)]
    Io(#[from] std::io::Error),
}

/// Fields from the deb control file that matter for conversion.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct DebControl {
    pub package: String,
    pub name: Option<String>,
    pub version: String,
    pub architecture: String,
    pub depends: Vec<String>,
    pub description: Option<String>,
}

impl DebControl {
    /// Parse a deb control file (continuation lines are folded in v1).
    pub fn parse(text: &str) -> Self {
        let mut c = DebControl::default();
        for line in text.lines() {
            let trimmed = line.trim();
            if trimmed.is_empty() {
                continue;
            }
            // Continuation lines start with whitespace.
            if line.chars().next().map(|c| c.is_whitespace()).unwrap_or(false) {
                continue;
            }
            if let Some((k, v)) = line.split_once(':') {
                let val = v.trim();
                match k.trim() {
                    "Package" => c.package = val.to_string(),
                    "Name" => c.name = Some(val.to_string()),
                    "Version" => c.version = val.to_string(),
                    "Architecture" => c.architecture = val.to_string(),
                    "Depends" => {
                        c.depends = val
                            .split(',')
                            .map(|d| d.trim().split(|ch: char| ch == ' ' || ch == '(').next().unwrap_or(d.trim()).to_string())
                            .filter(|d| !d.is_empty())
                            .collect()
                    }
                    "Description" => c.description = Some(val.to_string()),
                    _ => {}
                }
            }
        }
        c
    }
}

/// A file entry inside data.tar.
#[derive(Debug, Clone)]
pub struct DataEntry {
    pub path: String,
    pub size: u64,
    pub is_dir: bool,
    pub is_symlink: bool,
    pub mode: u32,
}

#[derive(Debug, Clone)]
pub struct DebArchive {
    pub control: DebControl,
    pub entries: Vec<DataEntry>,
    pub total_data_size: u64,
}

/// Normalize a data.tar entry path (e.g. "./usr/lib/libfoo.dylib") to its
/// absolute install path ("/usr/lib/libfoo.dylib"). Returns None for root
/// directory markers.
fn install_path(raw: &str) -> Option<String> {
    let p = raw.strip_prefix("./").unwrap_or(raw);
    if p.is_empty() || p == "." || p == "/" {
        return None;
    }
    Some(if p.starts_with('/') { p.to_string() } else { format!("/{p}") })
}

fn member_bytes<R: Read>(entry: &mut ar::Entry<R>) -> std::io::Result<Vec<u8>> {
    let mut out = Vec::new();
    entry.read_to_end(&mut out)?;
    Ok(out)
}

fn decoded(name: &str, bytes: Vec<u8>) -> Result<Box<dyn Read>, ParseError> {
    if name.ends_with(".gz") {
        // Pure-Rust gzip decode (flate2 rust_backend).
        Ok(Box::new(flate2::read::GzDecoder::new(IoCursor::new(bytes))))
    } else if name.ends_with(".xz") {
        // Pure-Rust xz decode (lzma-rs).
        let mut out = Vec::new();
        lzma_rs::xz_decompress(&mut bytes.as_slice(), &mut out)
            .map_err(|e| ParseError::InvalidDeb(format!("xz decode failed: {e}")))?;
        Ok(Box::new(IoCursor::new(out)))
    } else if name.ends_with(".zst") {
        // Pure-Rust zstd decode (ruzstd).
        let mut out = Vec::new();
        let mut decoder = ruzstd::StreamingDecoder::new(IoCursor::new(bytes))
            .map_err(|e| ParseError::InvalidDeb(format!("zstd decode failed: {e}")))?;
        decoder.read_to_end(&mut out)?;
        Ok(Box::new(IoCursor::new(out)))
    } else if name.ends_with(".tar") {
        Ok(Box::new(IoCursor::new(bytes)))
    } else {
        Err(ParseError::UnsupportedCompression(name.to_string()))
    }
}

/// Inspect a .deb: parse its control file and index every entry in data.tar.
/// NOTE(v0): members are read fully into memory; v1 streams data.tar to disk
/// so multi-hundred-MB packages stay within on-device memory limits.
pub fn inspect(path: &Path) -> Result<DebArchive, ParseError> {
    let file = File::open(path)?;
    let mut archive = ar::Archive::new(BufReader::new(file));

    let mut control: Option<DebControl> = None;
    let mut entries: Vec<DataEntry> = Vec::new();
    let mut total_data_size = 0u64;

    while let Some(entry) = archive.next_entry() {
        let mut entry = entry?;
        let name = String::from_utf8_lossy(entry.header().identifier()).to_string();
        if name == "debian-binary" {
            continue;
        }
        let bytes = member_bytes(&mut entry)?;

        if name.starts_with("control.tar") {
            let mut tar = tar::Archive::new(decoded(&name, bytes)?);
            for e in tar.entries()? {
                let mut e = e?;
                let p = e.header().path()?.to_string_lossy().to_string();
                if p == "control" || p == "./control" {
                    let mut s = String::new();
                    e.read_to_string(&mut s)?;
                    control = Some(DebControl::parse(&s));
                }
            }
        } else if name.starts_with("data.tar") {
            let mut tar = tar::Archive::new(decoded(&name, bytes)?);
            for e in tar.entries()? {
                let e = e?;
                let raw = e.header().path()?.to_string_lossy().to_string();
                let Some(p) = install_path(&raw) else {
                    continue;
                };
                let header = e.header();
                entries.push(DataEntry {
                    path: p,
                    size: header.size()?,
                    is_dir: header.entry_type().is_dir(),
                    is_symlink: header.entry_type().is_symlink(),
                    mode: header.mode()? as u32,
                });
                total_data_size += header.size()?;
            }
        } else {
            return Err(ParseError::InvalidDeb(format!("unexpected member '{name}'")));
        }
    }

    let control = control.ok_or_else(|| ParseError::MissingMember("control.tar.*".into()))?;
    if entries.is_empty() {
        return Err(ParseError::MissingMember("data.tar.*".into()));
    }
    Ok(DebArchive { control, entries, total_data_size })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_control_fields() {
        let c = DebControl::parse(
            "Package: demo.app\nVersion: 1.2.3-1\nArchitecture: iphoneos-arm64\nDepends: firmware (>= 16.0), libfoo\nDescription: Demo\n"
        );
        assert_eq!(c.package, "demo.app");
        assert_eq!(c.version, "1.2.3-1");
        assert_eq!(c.architecture, "iphoneos-arm64");
        assert_eq!(c.depends, vec!["firmware", "libfoo"]);
    }
}
