import SwiftUI
import UniformTypeIdentifiers

enum FlowPhase {
    case pick
    case analyzing
    case plan
    case converting
    case result
}

struct ConvertFlowView: View {
    @State private var phase: FlowPhase = .pick
    @State private var debURL: URL?
    @State private var showImporter = false

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .pick:
                    PickView(coreVersion: ConvertEngine.coreVersion) {
                        showImporter = true
                    }
                case .analyzing:
                    ProgressView("Analyzing package…")
                case .plan:
                    // TODO(v1): analysis card + editable plan review
                    EmptyView()
                case .converting:
                    ProgressView("Converting…")
                case .result:
                    ResultView(debURL: debURL) {
                        phase = .pick
                    }
                }
            }
            .navigationTitle("Deb2IPA")
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: ConvertFlowView.debTypes,
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        debURL = url
                        // TODO(v1): security-scoped read + ConvertEngine.analyze(url)
                        phase = .result
                    }
                case .failure(let error):
                    print("File import failed: \(error)")
                }
            }
            .onOpenURL { url in
                // A .deb opened from the Files app lands here (the type is
                // declared via CFBundleDocumentTypes / UTImportedTypeDeclarations
                // in Info.plist, so iOS offers Deb2IPA for .deb files).
                debURL = url
                phase = .result
            }
        }
    }

    /// The .deb document type, declared in Info.plist so both the system
    /// document picker and the Files app recognise Debian packages.
    static var debTypes: [UTType] {
        [UTType("org.debian.debian-package") ?? UTType(filenameExtension: "deb") ?? .data]
    }
}

struct PickView: View {
    let coreVersion: String
    let onPick: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "shippingbox")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Drop in a .deb, get out an installable .ipa")
                .font(.headline)
                .multilineTextAlignment(.center)
            Button("Choose package", action: onPick)
                .buttonStyle(.borderedProminent)
            Text("Core engine " + coreVersion)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

struct ResultView: View {
    let debURL: URL?
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.badge.gearshape")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Package received")
                .font(.headline)
            Text(debURL?.lastPathComponent ?? "unknown")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("The conversion pipeline lands in v1. The Rust core already inspects and classifies debs — the next milestone wires this screen to it.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Pick another", action: onDone)
                .buttonStyle(.bordered)
        }
        .padding()
    }
}
