import AppKit

// Renders a 1024×1024 app icon: a rounded-rect indigo→purple gradient with a
// white microphone glyph. Usage: swift make-icon.swift <out.png>
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let dim: CGFloat = 1024

let image = NSImage(size: NSSize(width: dim, height: dim))
image.lockFocus()

let full = NSRect(x: 0, y: 0, width: dim, height: dim)
let inset = dim * 0.08
let iconRect = full.insetBy(dx: inset, dy: inset)
let radius = iconRect.width * 0.2237

NSGraphicsContext.saveGraphicsState()
NSBezierPath(roundedRect: iconRect, xRadius: radius, yRadius: radius).addClip()
let gradient = NSGradient(colors: [
    NSColor(srgbRed: 0.36, green: 0.34, blue: 0.86, alpha: 1.0),
    NSColor(srgbRed: 0.62, green: 0.28, blue: 0.80, alpha: 1.0),
])
gradient?.draw(in: iconRect, angle: -90)
NSGraphicsContext.restoreGraphicsState()

if let mic = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil) {
    let config = NSImage.SymbolConfiguration(pointSize: dim * 0.46, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let sym = mic.withSymbolConfiguration(config) {
        let s = sym.size
        sym.draw(in: NSRect(x: (dim - s.width) / 2, y: (dim - s.height) / 2, width: s.width, height: s.height))
    }
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("icon render failed\n".utf8))
    exit(1)
}
do {
    try png.write(to: URL(fileURLWithPath: outPath))
    print("wrote \(outPath)")
} catch {
    FileHandle.standardError.write(Data("write failed: \(error)\n".utf8))
    exit(1)
}
