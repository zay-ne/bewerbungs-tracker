// Erzeugt das App-Icon aus dem Schriftzug und schneidet ihn für die Oberfläche zu.
//
// Große Größen tragen den ganzen Schriftzug, kleine nur das türkise „zap":
// bei 16 oder 32 Punkten wären sieben Zeichen nur noch ein Fleck.
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

/// Ab dieser Kantenlänge trägt das Icon den vollen Schriftzug.
let VOLL_AB = 128
/// Anteil der Kachelbreite, den das Motiv einnimmt.
let BREITE_VOLL: CGFloat = 0.88
let BREITE_KURZ: CGFloat = 0.66

func roundedPath(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

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

/// Liest die Grundfarbe des Logos aus der linken oberen Ecke.
func grundfarbe(_ image: CGImage) -> CGColor {
    guard let d = punkte(image), d.count >= 4, d[3] > 127 else {
        return CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    }
    let a = CGFloat(d[3]) / 255
    return CGColor(red: CGFloat(d[0]) / 255 / a, green: CGFloat(d[1]) / 255 / a,
                   blue: CGFloat(d[2]) / 255 / a, alpha: 1)
}

/// Schneidet die durchsichtigen Ränder weg.
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

/// Nur das türkise „zap": alles links der ersten schwarzen Spalte.
func kurzform(_ image: CGImage) -> CGImage? {
    guard let d = punkte(image) else { return nil }
    let w = image.width, h = image.height
    var grenze = w
    suche: for x in 0..<w {
        for y in 0..<h {
            let o = (y * w + x) * 4
            // Nur voll deckende Punkte prüfen: halbdurchsichtiges Türkis wirkt im
            // vormultiplizierten Feld dunkel und würde als Schwarz gelten.
            guard d[o + 3] > 235 else { continue }
            if d[o] < 70 && d[o + 1] < 70 && d[o + 2] < 70 {
                grenze = x
                break suche
            }
        }
    }
    // Ein Hauch Abstand, damit von der weichen Kante des schwarzen „p" nichts stehen bleibt
    grenze -= max(2, w / 150)
    guard grenze > 16 else { return nil }
    return image.cropping(to: CGRect(x: 0, y: 0, width: grenze, height: h))
        .flatMap { zugeschnitten($0) }
}

func drawIcon(size: CGFloat, motiv: CGImage, anteil: CGFloat, grund: CGColor) -> CGImage? {
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
    ctx.setFillColor(grund)
    ctx.fill(shape)

    let breite = shape.width * anteil
    let hoehe = breite * CGFloat(motiv.height) / CGFloat(motiv.width)
    ctx.draw(motiv, in: CGRect(x: shape.midX - breite / 2, y: shape.midY - hoehe / 2,
                               width: breite, height: hoehe))
    ctx.restoreGState()

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
let grund = grundfarbe(logo)
let kurz = kurzform(schriftzug) ?? schriftzug

func motivFür(_ px: Int) -> (CGImage, CGFloat) {
    px >= VOLL_AB ? (schriftzug, BREITE_VOLL) : (kurz, BREITE_KURZ)
}

// Vierter Pfad (optional): Icons und Schriftzug für die Oberfläche
if args.count > 4 {
    let webDir = URL(fileURLWithPath: args[4])
    for px in [180, 512] {
        let (motiv, anteil) = motivFür(px)
        guard let image = drawIcon(size: CGFloat(px), motiv: motiv, anteil: anteil, grund: grund) else { exit(1) }
        schreibe(image, breite: px, hoehe: px, nach: webDir.appendingPathComponent("icon-\(px).png"))
    }
    // Für den Reiter im Browser reicht das kurze Motiv
    if let klein = drawIcon(size: 64, motiv: kurz, anteil: BREITE_KURZ, grund: grund) {
        schreibe(klein, breite: 64, hoehe: 64, nach: webDir.appendingPathComponent("icon-64.png"))
    }
    schreibe(schriftzug, breite: schriftzug.width, hoehe: schriftzug.height,
             nach: webDir.appendingPathComponent("wortmarke.png"))
    print("Wortmarke: \(schriftzug.width)×\(schriftzug.height) · Kurzform: \(kurz.width)×\(kurz.height)")
}

for entry in sizes {
    let (motiv, anteil) = motivFür(entry.px)
    guard let image = drawIcon(size: CGFloat(entry.px), motiv: motiv, anteil: anteil, grund: grund) else { exit(1) }
    schreibe(image, breite: entry.px, hoehe: entry.px, nach: out.appendingPathComponent(entry.name))
}
print("Icon erzeugt: \(out.path)")
