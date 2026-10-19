import Foundation

/// One-time Google Cloud setup is required (see README "Google Drive setup"):
/// replace this placeholder with the client ID of your OAuth iOS client
/// (bundle ID com.ddrai.deb2ipa), and set the matching reversed-client-ID
/// URL scheme in CFBundleURLTypes in ios/project.yml.
enum GoogleDriveConfig {
    static let clientID = "REPLACE_WITH_GOOGLE_IOS_CLIENT_ID.apps.googleusercontent.com"

    /// Read-only access to Google Drive.
    static let driveScope = "https://www.googleapis.com/auth/drive.readonly"
}
