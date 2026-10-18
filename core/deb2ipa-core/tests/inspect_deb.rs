//! End-to-end fixture test: build a realistic deb on the fly (ar + gzip'd
//! control.tar/data.tar with "./"-prefixed paths, like real Cydia packages)
//! and verify inspect() + classify() see it the way the pipeline expects.

use deb2ipa_core::classifier::{classify, PayloadClass};
use deb2ipa_core::parser::inspect;
use std::io::Write;
use std::path::Path;

/// One GNU ar member (header + data), padded to even length.
fn ar_member(name: &str, data: &[u8]) -> Vec<u8> {
    let mut out = Vec::new();
    out.extend_from_slice(format!("{:<16}", format!("{name}/")).as_bytes());
    out.extend_from_slice(b"0           "); // mtime (12)
    out.extend_from_slice(b"0     "); // uid (6)
    out.extend_from_slice(b"0     "); // gid (6)
    out.extend_from_slice(format!("{:<8}", "100644").as_bytes()); // mode (8)
    out.extend_from_slice(format!("{:<10}", data.len()).as_bytes()); // size (10)
    out.extend_from_slice(b"`\n"); // fmag
    out.extend_from_slice(data);
    if data.len() % 2 == 1 {
        out.push(0x0a);
    }
    out
}

/// A gzipped tar containing the given (path, bytes) entries.
fn tar_gz(files: &[(&str, &[u8])]) -> Vec<u8> {
    let mut tar_bytes = Vec::new();
    {
        let mut builder = tar::Builder::new(&mut tar_bytes);
        for (name, data) in files {
            let mut header = tar::Header::new_gnu();
            header.set_size(data.len() as u64);
            header.set_mode(0o755);
            header.set_entry_type(tar::EntryType::Regular);
            header.set_cksum();
            builder.append_data(&mut header, name, *data).unwrap();
        }
        builder.finish().unwrap();
    }
    let mut gz = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::default());
    gz.write_all(&tar_bytes).unwrap();
    gz.finish().unwrap()
}

/// Build a realistic deb: control.tar.gz + data.tar.gz with "./"-style paths,
/// exactly like a package built with dpkg-deb for an iOS repo.
fn build_deb(path: &Path) {
    let mut deb: Vec<u8> = b"!<arch>\n".to_vec();

    let control = b"Package: demo.app\nName: Demo\nVersion: 1.0-1\nArchitecture: iphoneos-arm64\nDepends: libfoo (>= 1.0)\nDescription: Demo app\n";
    let control_tar = tar_gz(&[("./control", control)]);

    let mut data_files: Vec<(&str, &[u8])> = vec![
        ("./Applications/Demo.app/Demo", b"\xcf\xfa\xed\xfe"),
        ("./Applications/Demo.app/Info.plist", b"stub-plist"),
        ("./usr/lib/libfoo.dylib", b"\xcf\xfa\xed\xfe"),
        ("./usr/share/doc/demo/copyright", b"2026"),
    ];
    data_files.push(("./", b""));
    let data_tar = tar_gz(&data_files);

    deb.extend(ar_member("debian-binary", b"2.0\n"));
    deb.extend(ar_member("control.tar.gz", &control_tar));
    deb.extend(ar_member("data.tar.gz", &data_tar));
    std::fs::write(path, deb).unwrap();
}

#[test]
fn inspects_and_classifies_a_realistic_deb() {
    let path = std::env::temp_dir().join(format!("deb2ipa-test-{}.deb", std::process::id()));
    build_deb(&path);

    let deb = inspect(&path).expect("deb should parse");

    assert_eq!(deb.control.package, "demo.app");
    assert_eq!(deb.control.name.as_deref(), Some("Demo"));
    assert_eq!(deb.control.version, "1.0-1");
    assert_eq!(deb.control.architecture, "iphoneos-arm64");
    assert_eq!(deb.control.depends, vec!["libfoo"]);

    // Entry paths must be normalized to absolute install paths.
    let paths: Vec<&str> = deb.entries.iter().map(|e| e.path.as_str()).collect();
    assert!(paths.contains(&"/Applications/Demo.app/Demo"), "got {paths:?}");
    assert!(paths.contains(&"/usr/lib/libfoo.dylib"));
    assert!(paths.contains(&"/usr/share/doc/demo/copyright"));
    assert!(!paths.iter().any(|p| p.starts_with("./")), "no raw './' paths may survive");

    // A GUI app under /Applications with helper libs -> StandaloneApp.
    assert_eq!(classify(&deb.entries), PayloadClass::StandaloneApp);

    std::fs::remove_file(&path).ok();
}
