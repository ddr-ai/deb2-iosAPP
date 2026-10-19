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
- Import .deb files from the Files app or directly from your Google Drive

## Repo layout
- core/ — Rust workspace; deb2ipa-core (deb parsing, classification, Mach-O editing, validation, C FFI)
- ios/ — SwiftUI app + share extension (XcodeGen spec in project.yml; the .xcodeproj is generated, not committed)
- scripts/make-xcframework.sh — builds the Rust core for iOS device + simulator and packages Deb2IPACore.xcframework
- .github/workflows/build.yml — CI: core tests, app tests, unsigned archive, pseudo-signed Deb2IPA.ipa, artifacts + releases

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

## Google Drive import (one-time Google Cloud setup)
Deb2IPA can sign in with your Google account and browse your Drive for .deb files. Google requires every OAuth client to be registered, so a one-time setup is needed:
1. Create a project at console.cloud.google.com and enable the Google Drive API for it
2. Configure the OAuth consent screen (user type External) and add your own Google account as a test user
3. Create credentials: OAuth client ID, application type iOS, bundle ID com.ddrai.deb2ipa
4. Copy the client ID (it ends in .apps.googleusercontent.com) into ios/Deb2IPA/Sources/GoogleDriveConfig.swift, and update the reversed client ID URL scheme in ios/project.yml (com.googleusercontent.apps.<client id>)
5. Rebuild (or let CI rebuild) and reinstall the app

Until this setup is done, the Drive button shows a configuration error — the Files app import keeps working meanwhile. The app only requests the read-only drive scope; it can list and download .deb files, nothing else.

## Honest limitations
- Substrate tweaks/hooks cannot run on non-jailbroken iOS (no process injection). Deb2IPA detects and explains instead of shipping broken IPAs.
- Linux ELF binaries cannot run natively on iOS and are rejected with an explanation.
- Maintainer scripts (postinst etc.) are translated or flagged — never executed on-device.
- Convert only software you are licensed to convert. No DRM circumvention, ever.

## License
MIT — see LICENSE.
