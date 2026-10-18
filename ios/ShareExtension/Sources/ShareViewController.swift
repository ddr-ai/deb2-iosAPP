import UIKit

/// Share extension entry point: receives .deb files from the share sheet.
/// TODO(v1): copy the shared .deb into the main app's Documents/Inbox and
/// open the main app to start the analysis flow.
class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let label = UILabel()
        label.text = "Received .deb — opening Deb2IPA…"
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
}
