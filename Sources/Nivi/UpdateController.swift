import AppKit
import Sparkle

/// Keeps the app up to date using Sparkle.
///
/// Sparkle downloads a small XML file (the "appcast") that lists the versions that
/// exist, checks its signature, and offers the newer one to the user. Everything
/// about that lives behind this one type, so the rest of the app only says
/// "check now" or "turn automatic checks on".
///
/// The feed address and the public signing key come from Info.plist
/// (`SUFeedURL` and `SUPublicEDKey`), which the Makefile fills in at build time.
final class UpdateController: NSObject {
    static let shared = UpdateController()

    private let updaterController: SPUStandardUpdaterController

    /// True when this build knows where to look for updates. A build made without a
    /// feed address still runs; it just never checks.
    let isConfigured: Bool

    private override init() {
        let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? ""
        let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        isConfigured = !feed.isEmpty && !publicKey.isEmpty
        // Start the updater ourselves rather than letting the controller do it. A
        // misconfigured feed then lands in our log instead of an alert in the user's face.
        updaterController = SPUStandardUpdaterController(startingUpdater: false,
                                                        updaterDelegate: nil,
                                                        userDriverDelegate: nil)
        super.init()
    }

    func start() {
        guard isConfigured else {
            Log.info("Updates: no feed configured in Info.plist, automatic checks are off")
            return
        }
        do {
            try updaterController.updater.start()
            Log.info("Updates: checking automatically = \(automaticallyChecks), every \(Int(updaterController.updater.updateCheckInterval))s")
        } catch {
            Log.error("Updates: Sparkle could not start: \(error.localizedDescription)")
        }
    }

    /// Asks now, and shows the usual Sparkle window with the release notes.
    func checkForUpdates() {
        guard isConfigured else {
            showNotConfiguredAlert()
            return
        }
        updaterController.updater.checkForUpdates()
    }

    /// Sparkle keeps this preference itself, so there is no second copy of it to
    /// fall out of step with the real setting.
    var automaticallyChecks: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set { updaterController.updater.automaticallyChecksForUpdates = newValue }
    }

    var lastCheckDescription: String {
        guard let date = updaterController.updater.lastUpdateCheckDate else { return "Never" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func showNotConfiguredAlert() {
        let alert = NSAlert()
        alert.messageText = "This build cannot check for updates"
        alert.informativeText = "It was built without an update feed address. Download the latest version by hand instead."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
