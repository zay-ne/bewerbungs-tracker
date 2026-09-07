// Erzeugt das App-Icon aus der gelieferten Logo-Datei: genau dieses Bild, vollflächig,
// in jeder Größe – ohne Beschneidung, ohne runde Ecken, ohne anderes Motiv für kleine
// Größen. Zusätzlich wird der Schriftzug für die Oberfläche freigestellt (nur die leeren
// Ränder fallen weg); er trägt die Anmeldung und den Kopf des Posters.
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

func bild(_ pfad: String) -> CGImage? {
    NSImage(contentsOf: URL(fileURLWithPath: pfad))?
        .cgImage(forProposedRect: nil, context: nil, hints: nil)
}

/// Bildpunkte eines Bildes als RGBA-Feld.
func punkte(_ image: CGImage) -> [UInt8]? {
    let w = image.width, h = image.height
    var daten = [UInt8](repeating: 0, count: w * h * 4)
    let ok = daten.withUnsafeMutableBytes { puffer -> Bool in
        guard let ctx = CGContext(data: puffer.baseAddress, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        return true
    }
    return ok ? daten : nil
}

/// Schneidet die durchsichtigen Ränder weg (nur für den Schriftzug der Oberfläche).
func zugeschnitten(_ image: CGImage) -> CGImage? {
    guard let d = punkte(image) else { return image }
    let w = image.width, h = image.height
    var minX = w, minY = h, maxX = -1, maxY = -1
    for y in 0..<h {
        for x in 0..<w where d[(y * w + x) * 4 + 3] > 8 {
            if x < minX { minX = x }
            if y < minY { minY = y }
            if x > maxX { maxX = x }
            if y > maxY { maxY = y }
        }
    }
    guard maxX >= minX, maxY >= minY else { return image }
    return image.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
}

/// Das Logo auf die gewünschte Kantenlänge bringen – vollflächig, unverändert.
func drawIcon(size: CGFloat, logo: CGImage) -> CGImage? {
    guard let ctx = CGContext(data: nil, width: Int(size), height: Int(size),
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high
    ctx.draw(logo, in: CGRect(x: 0, y: 0, width: size, height: size))
    return ctx.makeImage()
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
guard let rohSchrift = bild(args[3]), let schriftzug = zugeschnitten(rohSchrift) else {
    FileHandle.standardError.write(Data("Schriftzug nicht lesbar: \(args[3])\n".utf8))
    exit(1)
}
// Vierter Pfad (optional): Icons und Schriftzug für die Oberfläche
if args.count > 4 {
    let webDir = URL(fileURLWithPath: args[4])
    for px in [180, 512] {
        guard let image = drawIcon(size: CGFloat(px), logo: logo) else { exit(1) }
        schreibe(image, breite: px, hoehe: px, nach: webDir.appendingPathComponent("icon-\(px).png"))
    }
    schreibe(schriftzug, breite: schriftzug.width, hoehe: schriftzug.height,
             nach: webDir.appendingPathComponent("wortmarke.png"))
    print("Logo: \(logo.width)×\(logo.height) · Schriftzug: \(schriftzug.width)×\(schriftzug.height)")
}

for entry in sizes {
    guard let image = drawIcon(size: CGFloat(entry.px), logo: logo) else { exit(1) }
    schreibe(image, breite: entry.px, hoehe: entry.px, nach: out.appendingPathComponent(entry.name))
}
print("Icon erzeugt: \(out.path)")
