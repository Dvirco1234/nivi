import AppKit
import DictatoCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: DictationController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        InterfaceSettings.makeSureTheAppIsReachable()
        InterfaceSettings.applyToApp()
        NotificationCenter.default.addObserver(
            forName: InterfaceSettings.changed, object: nil, queue: .main) { _ in
            InterfaceSettings.applyToApp()
        }
        // If the app went away in the middle of a recording it never put the output
        // volume back, so the user is looking at a Mac we muted. Fix that first.
        SystemVolume.restoreAfterCrash()
        let controller = DictationController()
        controller.wireMenu()
        controller.start()
        // Debug-tab settings must not be left on in a build someone downloaded. Verbose
        // logging writes a line per global keystroke, and there is no visible switch to
        // turn it back off once the Debug tab is gone.
        if !DeveloperMode.isOn { Settings().verboseLogging = false }
        // Seed the layout tuning file at launch so it is there to edit without having
        // to open Preferences first to bring it into existence. A released build skips
        // the file entirely and uses the shipped numbers.
        UITuning.reload()
        self.controller = controller
        UpdateController.shared.start()
        Log.info("Dictato launched")
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // With the Dock icon off the app runs as an accessory, and macOS is known to lose
        // that policy after a window comes forward. Re-applying on every activation keeps
        // the Dock icon from reappearing on its own.
        InterfaceSettings.applyDockIcon()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        PreferencesWindow.show()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Quitting mid-recording must not leave the speakers off.
        SystemVolume.restoreAfterRecording()
    }
}
