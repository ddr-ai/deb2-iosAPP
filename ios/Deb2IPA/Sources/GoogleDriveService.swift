import Foundation
import GoogleSignIn
import UIKit

struct DriveFile: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let size: String?
    let modifiedTime: String?
}

private struct DriveFileList: Codable {
    let files: [DriveFile]?
}

enum DriveError: LocalizedError {
    case notSignedIn
    case noToken
    case requestFailed(Int)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Not signed in to Google."
        case .noToken:
            return "Couldn't obtain a Google access token."
        case .requestFailed(let code):
            return "Drive request failed (HTTP \(code))."
        }
    }
}

/// Google Drive access: OAuth via Google Sign-In, file listing and download
/// via the Drive REST v3 API. All network calls run off the main thread via
/// URLSession async APIs; published state updates on MainActor.
@MainActor
final class GoogleDriveService: ObservableObject {
    static let shared = GoogleDriveService()

    @Published private(set) var files: [DriveFile] = []
    @Published private(set) var isBusy = false
    @Published private(set) var accountName: String?
    @Published var errorMessage: String?

    private init() {}

    var isSignedIn: Bool {
        GIDSignIn.sharedInstance.currentUser != nil
    }

    private func configure() {
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: GoogleDriveConfig.clientID)
    }

    /// Call when the picker appears: silently restores a previous sign-in.
    func restoreIfNeededAndRefresh() {
        configure()
        if GIDSignIn.sharedInstance.currentUser != nil {
            refreshFileList()
            return
        }
        guard GIDSignIn.sharedInstance.hasPreviousSignIn() else { return }
        GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, _ in
            Task { @MainActor in
                guard let self else { return }
                self.accountName = user?.profile?.email
                if user != nil {
                    self.refreshFileList()
                }
            }
        }
    }

    func signIn() {
        configure()
        guard let presenting = Self.topmostViewController() else {
            errorMessage = "Couldn't find a window to present Google Sign-In."
            return
        }
        isBusy = true
        errorMessage = nil
        GIDSignIn.sharedInstance.signIn(
            withPresenting: presenting,
            hint: nil,
            additionalScopes: [GoogleDriveConfig.driveScope]
        ) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                self.isBusy = false
                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                self.accountName = result?.user.profile?.email
                self.refreshFileList()
            }
        }
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        accountName = nil
        files = []
    }

    /// Lists .deb files in the user's Drive.
    func refreshFileList() {
        isBusy = true
        errorMessage = nil
        Task { @MainActor in
            do {
                let token = try await freshToken()
                var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
                components.queryItems = [
                    URLQueryItem(name: "q", value: "name contains '.deb' and trashed = false"),
                    URLQueryItem(name: "pageSize", value: "200"),
                    URLQueryItem(name: "fields", value: "files(id,name,size,modifiedTime)")
                ]
                guard let url = components.url else { throw DriveError.notSignedIn }
                var request = URLRequest(url: url)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw DriveError.requestFailed((response as? HTTPURLResponse)?.statusCode ?? -1)
                }
                let decoded = try JSONDecoder().decode(DriveFileList.self, from: data)
                self.files = decoded.files ?? []
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.isBusy = false
        }
    }

    /// Downloads a Drive file into Documents/Downloads and returns its local URL.
    func download(_ file: DriveFile, completion: @escaping (Result<URL, Error>) -> Void) {
        isBusy = true
        Task { @MainActor in
            do {
                let token = try await freshToken()
                var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files/\(file.id)")!
                components.queryItems = [URLQueryItem(name: "alt", value: "media")]
                guard let url = components.url else { throw DriveError.notSignedIn }
                var request = URLRequest(url: url)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw DriveError.requestFailed((response as? HTTPURLResponse)?.statusCode ?? -1)
                }
                let destination = try Self.saveToDocuments(data: data, filename: file.name)
                completion(.success(destination))
            } catch {
                completion(.failure(error))
            }
            self.isBusy = false
        }
    }

    // MARK: - Private

    /// Returns a fresh access token, refreshing if needed.
    private func freshToken() async throws -> String {
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            throw DriveError.notSignedIn
        }
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            user.refreshTokensIfNeeded { refreshed, error in
                if let error {
                    cont.resume(throwing: error)
                } else if let token = refreshed?.accessToken.tokenString, !token.isEmpty {
                    cont.resume(returning: token)
                } else {
                    cont.resume(throwing: DriveError.noToken)
                }
            }
        }
    }

    private static func saveToDocuments(data: Data, filename: String) throws -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let downloadsDir = docs.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        var destination = downloadsDir.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: destination.path) {
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let base = (filename as NSString).deletingPathExtension
            let ext = (filename as NSString).pathExtension
            destination = downloadsDir.appendingPathComponent("\(base)-\(stamp).\(ext)")
        }
        try data.write(to: destination, options: .atomic)
        return destination
    }

    private static func topmostViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            if let window = scene.keyWindow {
                var top = window.rootViewController
                while let presented = top?.presentedViewController {
                    top = presented
                }
                if let top { return top }
            }
        }
        for scene in scenes {
            for window in scene.windows where window.isKeyWindow {
                var top = window.rootViewController
                while let presented = top?.presentedViewController {
                    top = presented
                }
                if let top { return top }
            }
        }
        return nil
    }
}
