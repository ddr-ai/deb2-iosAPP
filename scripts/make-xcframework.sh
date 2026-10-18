#!/usr/bin/env bash
# Build deb2ipa-core for iOS (device + simulator) and package a static
# XCFramework for the SwiftUI app. Requires: rustup, Xcode.
set -euo pipefail
cd "$(dirname "$0")/.."

IOS_TARGET=aarch64-apple-ios
SIM_TARGET=aarch64-apple-ios-sim

rustup target add "$IOS_TARGET" "$SIM_TARGET"

echo "==> cargo build (device: $IOS_TARGET)"
cargo build --release --target "$IOS_TARGET" --manifest-path core/Cargo.toml

echo "==> cargo build (simulator: $SIM_TARGET)"
cargo build --release --target "$SIM_TARGET" --manifest-path core/Cargo.toml

mkdir -p build/xcframework
rm -rf build/xcframework/Deb2IPACore.xcframework

echo "==> xcodebuild -create-xcframework"
xcodebuild -create-xcframework \
  -library "core/target/$IOS_TARGET/release/libdeb2ipa_core.a" \
  -headers core/deb2ipa-core/include \
  -library "core/target/$SIM_TARGET/release/libdeb2ipa_core.a" \
  -headers core/deb2ipa-core/include \
  -output build/xcframework/Deb2IPACore.xcframework

echo "Built: build/xcframework/Deb2IPACore.xcframework"
