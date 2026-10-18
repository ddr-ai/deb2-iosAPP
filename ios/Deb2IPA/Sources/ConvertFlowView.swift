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
                    // TODO(v1): gate checklist + share-sheet hand-off to SideStore
                    EmptyView()
                }
            }
            .navigationTitle("Deb2IPA")
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [debType],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    debURL = url
                    phase = .analyzing
                    // TODO(v1): ConvertEngine.analyze(url)
                }
            }
        }
    }

    private var debType: UTType {
        UTType(filenameExtension: "deb") ?? .data
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
