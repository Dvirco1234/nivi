import AppKit
import NiviCore

final class MenuBarController: NSObject {
    /// Nil while the user has the menu bar icon turned off. The item is created and thrown
    /// away rather than hidden, because a hidden status item still holds its slot in the
    /// menu bar on some macOS versions.
    ///
    /// The language glyphs are wider than tall (~1.8:1), so a square slot would clip
    /// their sides. Variable length lets the item size itself to the image.
    private var statusItem: NSStatusItem?
    private let menu = NSMenu()
    /// The last icon asked for, so it can be put back if the item is created again.
    private var currentImage: NSImage?
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
        let updates = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdatesClicked), keyEquivalent: "")
        updates.target = self
        menu.addItem(updates)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Nivi", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        setIcon(systemName: "hourglass")
        refreshLaunchAtLoginState()
        applyVisibility()
        NotificationCenter.default.addObserver(
            forName: InterfaceSettings.changed, object: nil, queue: .main) { [weak self] _ in
            self?.applyVisibility()
        }
    }

    /// Creates or removes the menu bar icon to match "Show in the menu bar".
    func applyVisibility() {
        let shouldShow = Settings().showInStatusBar
        if shouldShow, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.menu = menu
            item.button?.image = currentImage
            statusItem = item
        } else if !shouldShow, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
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
        currentImage = NSImage(systemSymbolName: systemName, accessibilityDescription: "Nivi")
        statusItem?.button?.image = currentImage
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
        // The menu bar is ~22pt tall; 14 leaves the vertical breathing room the
        // system icons have, so the glyph reads as part of the bar rather than
        // filling it edge to edge.
        let h: CGFloat = 14
        img.size = NSSize(width: h * aspect, height: h)
        img.isTemplate = true   // monochrome; macOS tints for light/dark menu bar
        currentImage = img
        statusItem?.button?.image = img
    }

    @objc private func startStopClicked() { onStartStop?() }
    @objc private func reloadClicked() { onReloadModel?() }

    @objc private func openLogsClicked() {
        NSWorkspace.shared.open(Log.logDirectory)
    }

    @objc private func openPreferencesClicked() { PreferencesWindow.show() }

    @objc private func checkForUpdatesClicked() {
        NSApp.activate(ignoringOtherApps: true)
        UpdateController.shared.checkForUpdates()
    }

    @objc private func launchAtLoginClicked() {
        LoginItem.set(!LoginItem.isEnabled)
        refreshLaunchAtLoginState()
    }

    private func refreshLaunchAtLoginState() {
        launchAtLoginItem.state = LoginItem.isEnabled ? .on : .off
    }
}
