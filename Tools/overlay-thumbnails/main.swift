import AppKit
import SwiftUI

// Puts the two real recording overlays on screen over a generated gradient, then has
// `screencapture` photograph that patch of screen. Run it through
// Tools/make-recording-thumbnails.sh, which compiles it and cleans up after it.
//
// Why a real screen capture instead of drawing the views into an offscreen image: the
// panel's background is `.ultraThinMaterial`, which only blurs what is genuinely behind
// it on screen. Rendered offscreen it comes out flat grey and the thumbnail stops
// looking like the app.

// MARK: - What the shoot produces

/// The size the thumbnails are shown at in Preferences. Everything here is measured as a
/// multiple of it so the two pictures keep the same shape.
///
/// Must match `recordingThumbnailWidth` and `recordingThumbnailHeight` in
/// `UITuning.shipped`. Change those and the pictures come out the wrong shape.
let thumbnailWidth: CGFloat = 132
let thumbnailHeight: CGFloat = 82

/// How much screen each shot covers, as a multiple of the thumbnail size.
///
/// The panel is photographed at three times, so a 296 point card fills about three
/// quarters of the width, close to how big it feels on a real screen. The notch bar is
/// shot from a little further back: at the panel's scale it filled the frame like a
/// banner, and that thumbnail has to read as a small bar at the top of a screen.
let panelStageScale: CGFloat = 3
let notchStageScale: CGFloat = 3.4

let outputDirectory = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

// MARK: - The colourful background

/// A stand-in wallpaper, generated here rather than read off the Mac it runs on. Using
/// the real desktop would make the thumbnails different for every person who regenerates
/// them, and would mean touching the user's wallpaper to get a good one.
struct ThumbnailBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.24, green: 0.30, blue: 0.72),
                         Color(red: 0.51, green: 0.33, blue: 0.78),
                         Color(red: 0.90, green: 0.47, blue: 0.55)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            // Two soft blooms so the background has some depth instead of reading as a
            // flat colour ramp, the way a photographic wallpaper would.
            GeometryReader { geo in
                RadialGradient(colors: [Color(red: 1.0, green: 0.72, blue: 0.42).opacity(0.55), .clear],
                               center: UnitPoint(x: 0.85, y: 0.18),
                               startRadius: 0, endRadius: geo.size.width * 0.55)
                RadialGradient(colors: [Color(red: 0.35, green: 0.85, blue: 0.95).opacity(0.45), .clear],
                               center: UnitPoint(x: 0.12, y: 0.85),
                               startRadius: 0, endRadius: geo.size.width * 0.5)
            }
        }
    }
}

// MARK: - A recording that never records

/// An overlay model filled with believable numbers. Nothing here touches the microphone:
/// the levels are a fixed curve and the target app is only a name and an icon.
func makeDemoModel() -> OverlayModel {
    let model = OverlayModel()
    model.phase = .recording(elapsed: 4.2)
    model.languageCode = "he"
    let notesPath = "/System/Applications/Notes.app"
    if FileManager.default.fileExists(atPath: notesPath) {
        model.targetAppName = "Notes"
        model.targetAppIcon = NSWorkspace.shared.icon(forFile: notesPath)
    } else {
        model.targetAppName = "Notes"
    }
    model.levels = speechLikeLevels(count: OverlayModel.waveformSlots)
    return model
}

/// A waveform that looks like someone talking: a few loud syllables, a couple of quiet
/// gaps, nothing perfectly regular. Fixed values, so every regeneration draws the same
/// wave and the two thumbnails do not disagree with each other.
func speechLikeLevels(count: Int) -> [Float] {
    let shape: [Float] = [0.10, 0.22, 0.48, 0.72, 0.55, 0.30, 0.14, 0.35, 0.68, 0.92,
                          0.74, 0.44, 0.20, 0.09, 0.26, 0.58, 0.83, 0.61, 0.38, 0.17,
                          0.31, 0.64, 0.88, 0.70, 0.42]
    return (0..<count).map { shape[$0 % shape.count] }
}

// MARK: - Windows

/// The background sheet the overlays are photographed against. It sits just under the
/// overlay level so nothing else on the Mac can slide in between them.
func makeStageWindow(frame: NSRect) -> NSWindow {
    let window = NSWindow(contentRect: frame,
                          styleMask: [.borderless],
                          backing: .buffered,
                          defer: false)
    window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
    window.isOpaque = true
    window.hasShadow = false
    window.ignoresMouseEvents = true
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    window.contentView = NSHostingView(rootView: ThumbnailBackground()
        .frame(width: frame.width, height: frame.height))
    window.setFrame(frame, display: true)
    return window
}

/// Where the camera notch sits on the display, if there is one.
///
/// Same reading as `NotchOverlayPanel` does, repeated here because that one is private to
/// the app. The thumbnail has to use the real measurements, otherwise the bar in the
/// picture is a different shape from the bar the user gets.
func notchArea(of screen: NSScreen) -> (left: CGFloat, width: CGFloat)? {
    guard screen.safeAreaInsets.top > 0,
          let leftArea = screen.auxiliaryTopLeftArea,
          let rightArea = screen.auxiliaryTopRightArea,
          rightArea.minX > leftArea.maxX else { return nil }
    return (leftArea.maxX, rightArea.minX - leftArea.maxX)
}

func topStripHeight(of screen: NSScreen) -> CGFloat {
    if screen.safeAreaInsets.top > 0 { return screen.safeAreaInsets.top }
    let menuBar = NSApp.mainMenu?.menuBarHeight ?? 0
    return menuBar > 0 ? menuBar : NSStatusBar.system.thickness
}

/// Hosts `NotchOverlayView` wherever we ask, instead of pinning itself to the top of the
/// real screen the way `NotchOverlayPanel` does. Capturing the top of the real screen
/// would drag in the user's own menu bar and wallpaper.
func makeNotchWindow(model: OverlayModel, screen: NSScreen) -> NSWindow {
    let notchWidth = notchArea(of: screen)?.width ?? 0
    let stripHeight = topStripHeight(of: screen)
    let width = NotchOverlayView.barWidth(notchWidth: notchWidth)
    let height = NotchOverlayView.barHeight(stripHeight: stripHeight, liveText: model.liveText)
    let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                         styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered,
                         defer: false)
    window.level = .statusBar
    window.backgroundColor = .clear
    window.isOpaque = false
    window.hasShadow = false
    window.ignoresMouseEvents = true
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    window.contentView = NSHostingView(rootView: NotchOverlayView(
        model: model, notchWidth: notchWidth, stripHeight: stripHeight))
    return window
}

// MARK: - Taking the picture

/// `screencapture -R` measures from the top-left of the main display, while windows are
/// placed from the bottom-left. This converts one to the other.
func topLeftRect(of frame: NSRect, on screen: NSScreen) -> NSRect {
    let flippedY = screen.frame.maxY - frame.maxY
    return NSRect(x: frame.minX, y: flippedY, width: frame.width, height: frame.height)
}

func capture(_ rect: NSRect, to url: URL) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-x", "-o",
                         "-R\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))",
                         url.path]
    try? process.run()
    process.waitUntilExit()
    print(process.terminationStatus == 0 ? "wrote \(url.path)" : "screencapture failed for \(url.path)")
}

/// Lets the window server finish drawing before the shutter goes. Blocking the main
/// thread would freeze the very windows we are waiting for, so the run loop keeps
/// turning.
func settle(seconds: TimeInterval) {
    RunLoop.current.run(until: Date().addingTimeInterval(seconds))
}

// MARK: - Run

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

guard let screen = NSScreen.main else {
    print("no screen")
    exit(1)
}

/// The display whose notch the bar is measured against.
///
/// It is picked out by name rather than taken from `NSScreen.main`, because "main" means
/// the display holding the active window, and with a second monitor plugged in that is
/// often the external one. Measuring there gives a notch width of zero, and the bar
/// shrinks to a small tab that looks nothing like what a MacBook shows.
let notchScreen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? screen
if notchScreen.safeAreaInsets.top == 0 {
    print("warning: no display with a camera notch — the notch thumbnail will show the small tab shape")
}
print("notch width: \(notchArea(of: notchScreen)?.width ?? 0), strip height: \(topStripHeight(of: notchScreen))")

let model = makeDemoModel()

/// Photographs one overlay against a fresh background, low on the left of the screen.
///
/// Not in the middle, on purpose. System prompts — a keychain password box, for one —
/// open dead centre and sit above every window level an app can ask for, so a shoot in
/// the middle of the screen quietly photographs the dialog instead. Down in the corner
/// the stage is out of their way, and it is above the Dock's level anyway.
///
/// The background sheet is drawn a little larger than the photographed area, so a
/// half-point rounding difference between window placement and screencapture's
/// coordinates cannot leave a sliver of the real desktop along an edge.
func shoot(scale: CGFloat, named name: String, place: (NSRect) -> NSWindow) {
    let width = (thumbnailWidth * scale).rounded()
    let height = (thumbnailHeight * scale).rounded()
    let margin: CGFloat = 60
    let stageFrame = NSRect(x: (screen.frame.minX + margin).rounded(),
                            y: (screen.frame.minY + margin).rounded(),
                            width: width, height: height)
    let bleed: CGFloat = 12
    let stage = makeStageWindow(frame: stageFrame.insetBy(dx: -bleed, dy: -bleed))
    stage.orderFrontRegardless()

    let overlay = place(stageFrame)
    overlay.orderFrontRegardless()
    // Long enough for the window server to draw the blur and for the panel's travelling
    // glow to reach a point on the edge where it is clearly visible.
    settle(seconds: 2.0)
    capture(topLeftRect(of: stageFrame, on: screen),
            to: outputDirectory.appendingPathComponent("\(name).png"))
    overlay.orderOut(nil)
    stage.orderOut(nil)
}

// Panel: floating in the middle of the background, the way it floats over the desktop.
shoot(scale: panelStageScale, named: "RecordingDisplayPanel") { stageFrame in
    let panel = OverlayPanel(model: model)
    panel.setFrame(NSRect(x: (stageFrame.midX - OverlayView.cardWidth / 2).rounded(),
                          y: (stageFrame.midY - OverlayView.collapsedHeight / 2).rounded(),
                          width: OverlayView.cardWidth,
                          height: OverlayView.cardHeight(liveText: model.liveText)),
                   display: true)
    return panel
}

// Notch: pinned to the top edge of the background, so the thumbnail reads as the top of a
// screen with the bar hanging off it.
shoot(scale: notchStageScale, named: "RecordingDisplayNotch") { stageFrame in
    let notch = makeNotchWindow(model: model, screen: notchScreen)
    notch.setFrameOrigin(NSPoint(x: (stageFrame.midX - notch.frame.width / 2).rounded(),
                                 y: stageFrame.maxY - notch.frame.height))
    return notch
}

exit(0)
