// Erzeugt das App-Icon aus der gelieferten Logo-Datei und schneidet den Schriftzug
// für die Oberfläche zu (nur die leeren Ränder, das Motiv bleibt unangetastet).
//
// Aufruf: makeicon <ziel.iconset> <logo.png> <schriftzug.png> [web-ordner]

import AppKit
import CoreGraphics

let sizes: [(px: Int, name: String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
]

/// Anteil der Kachel, den das Logo einnimmt. Etwas kleiner als die Kachel, damit die
/// runden Ecken nichts vom Motiv abschneiden – das Ausrufezeichen sitzt dicht am Rand.
let LOGO_ANTEIL: CGFloat = 0.90

func roundedPath(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func bild(_ pfad: String) -> CGImage? {
    NSImage(contentsOf: URL(fileURLWithPath: pfad))?
        .cgImage(forProposedRect: nil, context: nil, hints: nil)
}

/// Liest die Grundfarbe des Logos aus der linken oberen Ecke.
func grundfarbe(_ image: CGImage) -> CGColor {
    let cs = CGColorSpaceCreateDeviceRGB()
    var pixel = [UInt8](repeating: 255, count: 4)
    pixel.withUnsafeMutableBytes { puffer in
        if let ctx = CGContext(data: puffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                               bytesPerRow: 4, space: cs,
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            ctx.draw(image, in: CGRect(x: 0, y: -CGFloat(image.height - 1),
                                       width: CGFloat(image.width), height: CGFloat(image.height)))
        }
    }
    let a = CGFloat(pixel[3]) / 255
    guard a > 0.5 else { return CGColor(red: 1, green: 1, blue: 1, alpha: 1) }
    return CGColor(red: CGFloat(pixel[0]) / 255 / a, green: CGFloat(pixel[1]) / 255 / a,
                   blue: CGFloat(pixel[2]) / 255 / a, alpha: 1)
}

func drawIcon(size: CGFloat, logo: CGImage, grund: CGColor) -> CGImage? {
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: Int(size), height: Int(size),
                              bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    let inset = size * 0.012
    let shape = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)

    ctx.saveGState()
    ctx.addPath(roundedPath(shape, shape.width * 0.225))
    ctx.clip()

    // Grund in der Farbe des Logos: der schmale Rand fällt dadurch nicht auf
    ctx.setFillColor(grund)
    ctx.fill(shape)

    // Das Logo vollständig, nur mittig verkleinert – nichts wird zugeschnitten
    let kante = shape.width * LOGO_ANTEIL
    ctx.draw(logo, in: CGRect(x: shape.midX - kante / 2, y: shape.midY - kante / 2,
                              width: kante, height: kante))
    ctx.restoreGState()

    return ctx.makeImage()
}

/// Schneidet die vollständig durchsichtigen Ränder des Schriftzugs weg.
func zugeschnitten(_ image: CGImage) -> CGImage? {
    let w = image.width, h = image.height
    let cs = CGColorSpaceCreateDeviceRGB()
    var daten = [UInt8](repeating: 0, count: w * h * 4)
    let ok = daten.withUnsafeMutableBytes { puffer -> Bool in
        guard let ctx = CGContext(data: puffer.baseAddress, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        return true
    }
    guard ok else { return image }

    var minX = w, minY = h, maxX = -1, maxY = -1
    for y in 0..<h {
        for x in 0..<w where daten[(y * w + x) * 4 + 3] > 8 {
            if x < minX { minX = x }
            if y < minY { minY = y }
            if x > maxX { maxX = x }
            if y > maxY { maxY = y }
        }
    }
    guard maxX >= minX, maxY >= minY else { return image }
    return image.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
}

func schreibe(_ image: CGImage, breite: Int, hoehe: Int, nach url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: breite, height: hoehe)
    if let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: url)
    }
}

let args = CommandLine.arguments
guard args.count > 3 else {
    FileHandle.standardError.write(Data("Nutzung: makeicon <ziel.iconset> <logo.png> <schriftzug.png> [web-ordner]\n".utf8))
    exit(1)
}
let out = URL(fileURLWithPath: args[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

guard let logo = bild(args[2]) else {
    FileHandle.standardError.write(Data("Logo nicht lesbar: \(args[2])\n".utf8))
    exit(1)
}
guard let schriftzug = bild(args[3]) else {
    FileHandle.standardError.write(Data("Schriftzug nicht lesbar: \(args[3])\n".utf8))
    exit(1)
}
let grund = grundfarbe(logo)

// Vierter Pfad (optional): Icons und Schriftzug für die Oberfläche
if args.count > 4 {
    let webDir = URL(fileURLWithPath: args[4])
    for px in [180, 512] {
        guard let image = drawIcon(size: CGFloat(px), logo: logo, grund: grund) else { exit(1) }
        schreibe(image, breite: px, hoehe: px, nach: webDir.appendingPathComponent("icon-\(px).png"))
    }
    if let wort = zugeschnitten(schriftzug) {
        schreibe(wort, breite: wort.width, hoehe: wort.height,
                 nach: webDir.appendingPathComponent("wortmarke.png"))
        print("Wortmarke: \(wort.width)×\(wort.height)")
    }
}

for entry in sizes {
    guard let image = drawIcon(size: CGFloat(entry.px), logo: logo, grund: grund) else { exit(1) }
    schreibe(image, breite: entry.px, hoehe: entry.px, nach: out.appendingPathComponent(entry.name))
}
print("Icon erzeugt: \(out.path)")
