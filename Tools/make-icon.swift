import AppKit

// Rasterizes Resources/AppIcon.svg (macOS renders SVG natively via NSImage) into
// icon-1024.png (app icon source) and DictatoLogo.png (256px overlay/menu-bar logo).

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let svgURL = URL(fileURLWithPath: "Resources/AppIcon.svg")

guard let svg = NSImage(contentsOf: svgURL) else {
    FileHandle.standardError.write(Data("ERROR: cannot load \(svgURL.path)\n".utf8))
    exit(1)
}

func writePNG(_ img: NSImage, to path: String, px: Int) {
    let target = NSImage(size: NSSize(width: px, height: px))
    target.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    img.draw(in: NSRect(x: 0, y: 0, width: px, height: px),
             from: .zero, operation: .copy, fraction: 1.0)
    target.unlockFocus()
    guard let tiff = target.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: path))
}

writePNG(svg, to: "\(outDir)/icon-1024.png", px: 1024)
writePNG(svg, to: "\(outDir)/DictatoLogo.png", px: 256)
print("rasterized AppIcon.svg → icon-1024.png + DictatoLogo.png in \(outDir)")
