import Foundation

/// Thin wrapper over deb2ipa-core's C ABI (see core/deb2ipa-core/include/deb2ipa.h).
enum ConvertEngine {
    static var coreVersion: String {
        String(cString: deb2ipa_version())
    }

    // TODO(v1): analyze(url:) -> Analysis, convert(plan:) -> ConversionReport
}
