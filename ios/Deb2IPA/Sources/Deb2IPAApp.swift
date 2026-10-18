import SwiftUI

@main
struct Deb2IPAApp: App {
    init() {
        // Ensure Documents exists so the app's folder shows up in the Files
        // app (UIFileSharingEnabled) as soon as the app has launched once.
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        }
    }

    var body: some Scene {
        WindowGroup {
            ConvertFlowView()
        }
    }
}
