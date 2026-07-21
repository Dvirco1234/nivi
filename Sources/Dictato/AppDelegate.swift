import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: DictationController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let controller = DictationController()
        controller.wireMenu()
        controller.start()
        self.controller = controller
        Log.info("Dictato launched")
    }
}
