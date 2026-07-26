import AppKit
import DictatoCore

final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let statusMenuItem = NSMenuItem(title: "Loading…", action: nil, keyEquivalent: "")
    private let startStopItem = NSMenuItem(title: "Start Recording", action: #selector(startStopClicked), keyEquivalent: "")
    private let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(launchAtLoginClicked), keyEquivalent: "")

    var onStartStop: (() -> Void)?
    var onReloadModel: (() -> Void)?

    private var dictateHint = ""
    private var startStopBase = "Start Recording"
    private var primaryLanguage = "he"

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
        let prefs = NSMenuItem(title: "Preferences…", action: #selector(openPreferencesClicked), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)
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
        lastState = state
        switch state {
        case .loadingModel:
            statusMenuItem.title = "Loading Hebrew model…"
            startStopItem.isEnabled = false
            setIcon(systemName: "hourglass")
        case .idle:
            statusMenuItem.title = "Ready"
            startStopBase = "Start Recording"; applyStartStopTitle()
            startStopItem.isEnabled = true
            setLanguageGlyph()
        case .recording:
            statusMenuItem.title = "Recording…"
            startStopBase = "Stop Recording"; applyStartStopTitle()
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

    func setDictateHint(_ text: String) {
        dictateHint = text
        applyStartStopTitle()
    }

    private func applyStartStopTitle() {
        startStopItem.title = dictateHint.isEmpty ? startStopBase : "\(startStopBase)   \(dictateHint)"
    }

    private func setIcon(systemName: String) {
        statusItem.button?.image = NSImage(
            systemSymbolName: systemName, accessibilityDescription: "Dictato")
    }

    /// Primary (default) model's language drives the menu-bar glyph.
    func setPrimaryLanguage(_ language: String) {
        primaryLanguage = language
        if case .idle = lastState { setLanguageGlyph() }
    }

    private var lastState: DictationState = .loadingModel

    private func setLanguageGlyph() {
        guard let img = LanguageGlyph.image(named: LanguageGlyph.menuBarName(for: primaryLanguage)) else {
            setIcon(systemName: "waveform")
            return
        }
        let aspect = img.size.height > 0 ? img.size.width / img.size.height : 1
        let h: CGFloat = 16
        img.size = NSSize(width: h * aspect, height: h)
        img.isTemplate = true   // monochrome; macOS tints for light/dark menu bar
        statusItem.button?.image = img
    }

    @objc private func startStopClicked() { onStartStop?() }
    @objc private func reloadClicked() { onReloadModel?() }

    @objc private func openLogsClicked() {
        NSWorkspace.shared.open(Log.logDirectory)
    }

    @objc private func openPreferencesClicked() { PreferencesWindow.show() }

    @objc private func launchAtLoginClicked() {
        LoginItem.set(!LoginItem.isEnabled)
        refreshLaunchAtLoginState()
    }

    private func refreshLaunchAtLoginState() {
        launchAtLoginItem.state = LoginItem.isEnabled ? .on : .off
    }
}
