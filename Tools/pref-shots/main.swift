import AppKit
import SwiftUI

// Photographs one Preferences tab without opening the real app.
//
// Run it through Tools/make-pref-shots.sh, which compiles it and cleans up after it.
//
// Why this exists: checking that a settings row looks right used to mean opening the
// running app's Preferences window and clicking through to a tab. On the developer's own
// Mac that means taking over the screen, and clicking is done with synthetic input, which
// can trip Dictato's own hotkey and start a real recording. This tool puts the real
// section views in a window of its own and lets `screencapture` photograph them, so
// nothing is clicked and the app is never touched.
//
// It only draws. Nothing here records audio, registers a hotkey or writes a setting.

/// The size of the area a tab gets inside the real window: the 820 point minimum width
/// less the sidebar, and tall enough that a whole page fits without scrolling.
let pageWidth: CGFloat = 820 - UITuning.sidebarWidth
let pageHeight: CGFloat = 900

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count >= 3 else {
    print("usage: pref-shots <output-directory> <file-name-suffix> <tab-name> [tab-name ...]")
    exit(1)
}
let outputDirectory = URL(fileURLWithPath: arguments[0])
/// Keeps a debug shot from overwriting the release shot of the same tab, so the two
/// can be put side by side.
let fileSuffix = arguments[1]
let tabNames = Array(arguments.dropFirst(2))

/// The same blurred backing the real window has. A flat colour would make every card in
/// the picture read darker than it does in the app.
struct PageBackdrop<Content: View>: View {
    let content: Content
    var body: some View {
        ZStack {
            VisualEffect()
            content
        }
        .frame(width: pageWidth, height: pageHeight)
    }
}

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

@ViewBuilder func page(named name: String) -> some View {
    switch name {
    case "general": GeneralSection()
    case "speech": SpeechSection()
    case "layout": LayoutTuningSection()
    // The real sidebar tab list. Which tabs it contains is the whole point: Layout and
    // Debug are absent unless this was built with DEBUG defined.
    case "sidebar": SidebarPreview()
    default: Text("unknown tab \(name)")
    }
}

/// Draws the sidebar's tab list on the sidebar's own background, at the sidebar's width.
struct SidebarPreview: View {
    @State private var selection: PrefSection = .general
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarTabList(selection: $selection)
            Spacer(minLength: 0)
        }
        .frame(width: UITuning.sidebarWidth, alignment: .leading)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: UITuning.sidebarCorner))
        .padding(20)
    }
}

func settle(seconds: TimeInterval) {
    RunLoop.current.run(until: Date().addingTimeInterval(seconds))
}

/// `screencapture -R` measures down from the top-left of the screen, windows are placed
/// up from the bottom-left.
func capture(_ frame: NSRect, on screen: NSScreen, to url: URL) {
    let flippedY = screen.frame.maxY - frame.maxY
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-x", "-o",
                         "-R\(Int(frame.minX)),\(Int(flippedY)),\(Int(frame.width)),\(Int(frame.height))",
                         url.path]
    try? process.run()
    process.waitUntilExit()
    print(process.terminationStatus == 0 ? "wrote \(url.path)" : "screencapture failed for \(url.path)")
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

guard let screen = NSScreen.main else {
    print("no screen")
    exit(1)
}

for name in tabNames {
    // Down in a corner, not the middle: a system password box opens dead centre and sits
    // above every window level an app can ask for, so a shoot in the middle would
    // photograph the dialog instead.
    let frame = NSRect(x: (screen.frame.minX + 40).rounded(),
                       y: (screen.frame.minY + 40).rounded(),
                       width: pageWidth, height: pageHeight)
    // A non-activating panel so the window the user is typing in keeps the keyboard.
    let window = NSPanel(contentRect: frame,
                         styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered,
                         defer: false)
    window.level = .statusBar
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = false
    window.ignoresMouseEvents = true
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    window.contentView = NSHostingView(rootView: PageBackdrop(content: page(named: name)))
    window.setFrame(frame, display: true)
    window.orderFrontRegardless()
    settle(seconds: 1.2)
    capture(frame, on: screen, to: outputDirectory.appendingPathComponent("\(name)\(fileSuffix).png"))
    window.orderOut(nil)
}

exit(0)
