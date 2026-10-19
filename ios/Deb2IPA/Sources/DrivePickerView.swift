import SwiftUI

/// Sheet that lets the user connect to Google Drive and pick a .deb file.
struct DrivePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var drive = GoogleDriveService.shared
    let onPicked: (URL) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if !drive.isSignedIn {
                    signInView
                } else if drive.isBusy && drive.files.isEmpty {
                    ProgressView("Loading Drive…")
                } else if let error = drive.errorMessage, drive.files.isEmpty {
                    errorView(error)
                } else if drive.files.isEmpty {
                    emptyView
                } else {
                    fileList
                }
            }
            .navigationTitle("Google Drive")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if drive.isSignedIn {
                        Button("Sign out") { drive.signOut() }
                            .font(.footnote)
                    }
                }
            }
        }
        .onAppear { drive.restoreIfNeededAndRefresh() }
    }

    private var signInView: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.icloud")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Connect to Google Drive")
                .font(.headline)
            Text("Browse .deb files in your Drive and download them for conversion. Deb2IPA only requests read-only access.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button {
                drive.signIn()
            } label: {
                Label("Sign in with Google", systemImage: "person.badge.key")
            }
            .buttonStyle(.borderedProminent)
            if drive.isBusy {
                ProgressView()
            }
            if let error = drive.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
            Button("Retry") { drive.refreshFileList() }
                .buttonStyle(.bordered)
        }
        .padding()
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No .deb files found in your Drive")
                .foregroundStyle(.secondary)
        }
    }

    private var fileList: some View {
        List(drive.files) { file in
            Button {
                download(file)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(file.name)
                        .font(.body)
                        .lineLimit(1)
                    HStack(spacing: 12) {
                        if let size = file.size, let bytes = Int64(size) {
                            Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                        }
                        if let modified = file.modifiedTime {
                            Text(shortDate(modified))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func download(_ file: DriveFile) {
        drive.download(file) { result in
            switch result {
            case .success(let url):
                dismiss()
                onPicked(url)
            case .failure(let error):
                drive.errorMessage = error.localizedDescription
            }
        }
    }

    private func shortDate(_ iso: String) -> String {
        ISO8601DateFormatter().date(from: iso).map {
            DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .short)
        } ?? iso
    }
}
