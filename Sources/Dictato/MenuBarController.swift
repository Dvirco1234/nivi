import AppKit
import ServiceManagement
import DictatoCore

final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let statusMenuItem = NSMenuItem(title: "Loading…", action: nil, keyEquivalent: "")
    private let startStopItem = NSMenuItem(title: "Start Recording", action: #selector(startStopClicked), keyEquivalent: "")
    private let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(launchAtLoginClicked), keyEquivalent: "")

    var onStartStop: (() -> Void)?
    var onReloadModel: (() -> Void)?

    override init() {
        super.init()
        let menu = NSMenu()
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())
        startStopItem.target = self
        menu.addItem(startStopItem)
        let reload = NSMenuItem(title: "Reload Model", action: #selector(reloadClicked), keyEquivalent: "")
        reload.target = self
        menu.addItem(reload)
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)
        let logs = NSMenuItem(title: "Open Logs", action: #selector(openLogsClicked), keyEquivalent: "")
        logs.target = self
        menu.addItem(logs)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Dictato", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusItem.menu = menu
        setIcon(systemName: "hourglass")
        refreshLaunchAtLoginState()
    }

    func update(state: DictationState) {
        switch state {
        case .loadingModel:
            statusMenuItem.title = "Loading Hebrew model…"
            startStopItem.isEnabled = false
            setIcon(systemName: "hourglass")
        case .idle:
            statusMenuItem.title = "Ready"
            startStopItem.title = "Start Recording"
            startStopItem.isEnabled = true
            setIcon(systemName: "waveform")
        case .recording:
            statusMenuItem.title = "Recording…"
            startStopItem.title = "Stop Recording"
            startStopItem.isEnabled = true
            setIcon(systemName: "record.circle.fill")
        case .transcribing, .inserting:
            statusMenuItem.title = "Processing…"
            startStopItem.isEnabled = false
            setIcon(systemName: "ellipsis.circle")
        case .error(let message):
            statusMenuItem.title = "Error: \(message)"
            startStopItem.isEnabled = true
            setIcon(systemName: "exclamationmark.triangle")
        }
    }

    func setStatusText(_ text: String) {
        statusMenuItem.title = text
    }

    private func setIcon(systemName: String) {
        statusItem.button?.image = NSImage(
            systemSymbolName: systemName, accessibilityDescription: "Dictato")
    }

    @objc private func startStopClicked() { onStartStop?() }
    @objc private func reloadClicked() { onReloadModel?() }

    @objc private func openLogsClicked() {
        NSWorkspace.shared.open(Log.logDirectory)
    }

    @objc private func launchAtLoginClicked() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            Log.error("Launch at login toggle failed: \(error.localizedDescription)")
        }
        refreshLaunchAtLoginState()
    }

    private func refreshLaunchAtLoginState() {
        launchAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
}
