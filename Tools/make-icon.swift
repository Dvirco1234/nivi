import AppKit

// Draws a 1024x1024 Dictato icon: rounded blue tile, white mic, Hebrew aleph accent.
let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let rect = NSRect(x: 0, y: 0, width: size, height: size)

let bg = NSBezierPath(roundedRect: rect, xRadius: 220, yRadius: 220)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.20, green: 0.55, blue: 0.95, alpha: 1),
    NSColor(calibratedRed: 0.10, green: 0.25, blue: 0.65, alpha: 1),
])!
gradient.draw(in: bg, angle: -90)

// Microphone body
let mic = NSBezierPath(roundedRect: NSRect(x: 412, y: 470, width: 200, height: 320),
                       xRadius: 100, yRadius: 100)
NSColor.white.setFill()
mic.fill()
// Mic stand
let stand = NSBezierPath()
stand.move(to: NSPoint(x: 512, y: 470))
stand.line(to: NSPoint(x: 512, y: 300))
stand.lineWidth = 34
NSColor.white.setStroke()
stand.stroke()
let base = NSBezierPath(rect: NSRect(x: 420, y: 285, width: 184, height: 30))
base.fill()

// Hebrew aleph accent, bottom-right
let aleph = "א" as NSString
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 300, weight: .bold),
    .foregroundColor: NSColor.white.withAlphaComponent(0.9),
]
aleph.draw(at: NSPoint(x: 640, y: 120), withAttributes: attrs)

image.unlockFocus()

func writePNG(_ img: NSImage, to path: String, px: Int) {
    let target = NSImage(size: NSSize(width: px, height: px))
    target.lockFocus()
    img.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    target.unlockFocus()
    guard let tiff = target.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: path))
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
writePNG(image, to: "\(outDir)/icon-1024.png", px: 1024)
writePNG(image, to: "\(outDir)/DictatoLogo.png", px: 256)
print("wrote icon-1024.png + DictatoLogo.png to \(outDir)")
