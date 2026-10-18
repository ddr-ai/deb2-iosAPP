import Foundation

enum PayloadClass: String, Codable, CaseIterable {
    case standaloneApp
    case cliTool
    case substrateTweak
    case daemon
    case linuxElf
    case mixed
    case unknown

    var convertible: Bool {
        switch self {
        case .standaloneApp, .cliTool, .mixed:
            return true
        default:
            return false
        }
    }
}

struct ConversionWarning: Identifiable, Codable, Hashable {
    enum Severity: String, Codable {
        case blocking, risky, info
    }
    let severity: Severity
    let code: String
    let message: String
    var id: String { code }
}

struct PlanOptions: Codable, Hashable {
    var bundleId: String
    var displayName: String
    var version: String
}

struct ConversionReport: Codable, Hashable {
    var plan: PlanOptions
    var warnings: [ConversionWarning]
    var gatesPassed: Bool
}
