import AppKit

// Generic SVG → PNG rasterizer, aspect-preserving.
// Usage: rasterize <input.svg> <output.png> <longEdgePx>
guard CommandLine.arguments.count == 4,
      let px = Int(CommandLine.arguments[3]) else {
    FileHandle.standardError.write(Data("usage: rasterize <in.svg> <out.png> <px>\n".utf8))
    exit(2)
}
let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])

guard let svg = NSImage(contentsOf: input) else {
    FileHandle.standardError.write(Data("ERROR: cannot load \(input.path)\n".utf8))
    exit(1)
}

let src = svg.size
let aspect = src.width > 0 && src.height > 0 ? src.width / src.height : 1
let (w, h): (Int, Int) = aspect >= 1
    ? (px, max(1, Int((Double(px) / aspect).rounded())))
    : (max(1, Int((Double(px) * aspect).rounded())), px)

let target = NSImage(size: NSSize(width: w, height: h))
target.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .high
svg.draw(in: NSRect(x: 0, y: 0, width: w, height: h), from: .zero, operation: .copy, fraction: 1.0)
target.unlockFocus()

guard let tiff = target.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("ERROR: encode failed\n".utf8)); exit(1)
}
try? png.write(to: output)
print("rasterized \(input.lastPathComponent) → \(output.lastPathComponent) (\(w)x\(h))")
