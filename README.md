# deb2-iosAPP — Deb2IPA

![CI](https://github.com/ddr-ai/deb2-iosAPP/actions/workflows/build.yml/badge.svg)

Convert Debian (.deb) packages into sideloadable .ipa files — entirely on-device. No Mac, no jailbreak. Deb2IPA is a native SwiftUI iOS app backed by a Rust conversion core, and it is itself built and distributed as a sideloadable .ipa by GitHub Actions.

Status: early scaffold — but the pipeline is fully green. Every push to main runs the Rust core tests, builds the iOS XCFramework, runs the app tests on an iPhone simulator, archives unsigned, and publishes a pseudo-signed Deb2IPA.ipa artifact. The in-app conversion flow is still stubbed with clear TODOs; the architecture, project generation and CI are real and working.

## Features (target)
- On-device .deb parsing (ar + tar, gzip/xz/zstd) — pure library calls, no shell, no external tools
- Payload classification: standalone app, CLI tool, substrate tweak, daemon, Linux ELF — with honest verdicts
- Mach-O surgery: relocate bundled dylibs and rewrite LC_LOAD_DYLIB / LC_ID_DYLIB / LC_RPATH so every dependency resolves inside the app sandbox
- Info.plist repair/synthesis + icon generation
- Pre-flight validation gates (structure, plist, signature, load commands, sandbox): no IPA is exported unless every gate passes
- Hand-off signing: export the finished .ipa and open it in SideStore / AltStore / Sideloadly, which apply your Apple ID signature
- Import .deb files from the Files app (document picker + hand-off via the .deb document type)

## Repo layout
- core/ — Rust workspace; deb2ipa-core (deb parsing, classification, Mach-O editing, validation, C FFI)
- ios/ — SwiftUI app + share extension (XcodeGen spec in project.yml; the .xcodeproj is generated, not committed)
- web/ — browser-based .deb inspector, published to GitHub Pages (static, no build step)
- scripts/make-xcframework.sh — builds the Rust core for iOS device + simulator and packages Deb2IPACore.xcframework
- .github/workflows/build.yml — CI: core tests, app tests, unsigned archive, pseudo-signed Deb2IPA.ipa, artifacts + releases
- .github/workflows/pages.yml — deploys web/ to GitHub Pages

## Build locally
1. Install Xcode, Rust, XcodeGen, ldid (brew install xcodegen ldid)
2. rustup target add aarch64-apple-ios aarch64-apple-ios-sim
3. scripts/make-xcframework.sh
4. cd ios && xcodegen generate && open Deb2IPA.xcodeproj

## CI and download
Every push uploads a Deb2IPA-ipa artifact; tags publish GitHub Releases; a nightly cron keeps a rolling nightly release. The CI-built IPA is pseudo-signed (ldid); the real Apple ID signature is applied at sideload time by SideStore/AltStore/Sideloadly. No Apple secrets live in CI.

## Sideload
1. Download Deb2IPA.ipa from Releases (or the latest CI artifact)
2. Open it with SideStore/AltStore on-device (or sideload via USB with Sideloadly)
3. Launch. Free Apple IDs sign for 7 days; SideStore/AltStore refresh automatically on-device

## Web inspector (GitHub Pages)
https://ddr-ai.github.io/deb2-iosAPP/ runs the same honest-verdict analysis in any phone browser — iOS included. Pick a .deb from the local file picker (on iPhone that is the Files app, including iCloud Drive) and get: package metadata, the ar/tar structure, a full file listing with per-file download, and a classification verdict (ARM64 app bundle / MobileSubstrate tweak / Linux ELF / data-only package). Everything runs client-side — no file is ever uploaded. gzip members decode with the browser's native DecompressionStream; xz/zstd/bzip2 members fall back to a libarchive.js WASM helper loaded from a CDN (jsDelivr, unpkg as backup).

One-time setup: in the repo, go to Settings → Pages → Build and deployment → Source: "GitHub Actions". The pages workflow then publishes web/ on every push that touches it, and any time via manual dispatch from the Actions tab.

## Honest limitations
- Substrate tweaks/hooks cannot run on non-jailbroken iOS (no process injection). Deb2IPA detects and explains instead of shipping broken IPAs.
- Linux ELF binaries cannot run natively on iOS and are rejected with an explanation.
- Maintainer scripts (postinst etc.) are translated or flagged — never executed on-device.
- Convert only software you are licensed to convert. No DRM circumvention, ever.

## License
MIT — see LICENSE.
