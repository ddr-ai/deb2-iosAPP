import Foundation

/// Google OAuth iOS client (bundle ID com.ddrai.deb2ipa).
/// Registered in Google Cloud Console; see README "Google Drive import".
enum GoogleDriveConfig {
    static let clientID = "109123923843-jfqi949v87ok6bcoi582hgovll8b53lk.apps.googleusercontent.com"

    /// Read-only access to Google Drive.
    static let driveScope = "https://www.googleapis.com/auth/drive.readonly"
}
