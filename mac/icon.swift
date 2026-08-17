// Erzeugt das App-Icon (blaues Squircle mit aufsteigenden Balken) als .iconset.
// Aufruf: makeicon <ziel.iconset>

import AppKit
import CoreGraphics

let sizes: [(px: Int, name: String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
]

func roundedPath(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func drawIcon(size: CGFloat) -> CGImage? {
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: Int(size), height: Int(size),
                              bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    // Grundform: gerundetes Quadrat, ganz leicht eingerückt
    let inset = size * 0.012
    let shape = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = shape.width * 0.225

    ctx.saveGState()
    ctx.addPath(roundedPath(shape, radius))
    ctx.clip()

    // Heller Verlauf: fast weiß in der Mitte, zart blau nach außen
    let colors = [
        CGColor(red: 0.988, green: 0.992, blue: 1.0, alpha: 1),
        CGColor(red: 0.925, green: 0.945, blue: 0.992, alpha: 1),
        CGColor(red: 0.855, green: 0.890, blue: 0.976, alpha: 1),
    ] as CFArray
    if let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 0.55, 1]) {
        ctx.drawRadialGradient(grad,
                               startCenter: CGPoint(x: shape.midX, y: shape.midY), startRadius: 0,
                               endCenter: CGPoint(x: shape.midX, y: shape.midY), endRadius: shape.width * 0.78,
                               options: [.drawsAfterEndLocation])
    }

    // Vier runde Spitzen (Kreisbögen) mit tangential anschließenden, eingezogenen Kanten
    let cx = shape.midX, cy = shape.midY
    let r = shape.width * 0.315          // Abstand der Spitzen zur Mitte
    let rt = r * 0.42                    // Rundung der Spitzen
    let c = r - rt                       // Mittelpunkt eines Spitzenbogens
    let phi = CGFloat.pi * 65 / 180      // halbe Öffnung des Bogens
    let reach = r * 0.25                 // Länge der Tangenten -> Tiefe der Taille

    func onAxis(_ a: CGFloat) -> CGPoint { CGPoint(x: cx + c * cos(a), y: cy + c * sin(a)) }
    func shoulder(_ axis: CGFloat, _ off: CGFloat) -> (point: CGPoint, tangent: CGPoint) {
        let a = axis + off
        let mid = onAxis(axis)
        return (CGPoint(x: mid.x + rt * cos(a), y: mid.y + rt * sin(a)),
                CGPoint(x: -sin(a), y: cos(a)))
    }

    let path = CGMutablePath()
    let axes: [CGFloat] = [0, .pi / 2, .pi, .pi * 1.5]
    path.move(to: shoulder(axes[0], -phi).point)

    for (i, axis) in axes.enumerated() {
        let mid = onAxis(axis)
        path.addArc(center: mid, radius: rt, startAngle: axis - phi, endAngle: axis + phi, clockwise: false)

        let out = shoulder(axis, phi)
        let nextAxis = axes[(i + 1) % 4]
        let inn = shoulder(nextAxis, -phi)
        path.addCurve(to: inn.point,
                      control1: CGPoint(x: out.point.x + out.tangent.x * reach,
                                        y: out.point.y + out.tangent.y * reach),
                      control2: CGPoint(x: inn.point.x - inn.tangent.x * reach,
                                        y: inn.point.y - inn.tangent.y * reach))
    }
    path.closeSubpath()

    ctx.addPath(path)
    ctx.setStrokeColor(CGColor(red: 0.337, green: 0.333, blue: 0.573, alpha: 1))
    ctx.setLineWidth(size * 0.077)
    ctx.setLineJoin(.round)
    ctx.setLineCap(.round)
    ctx.strokePath()
    ctx.restoreGState()

    return ctx.makeImage()
}

let args = CommandLine.arguments
guard args.count > 1 else {
    FileHandle.standardError.write(Data("Nutzung: makeicon <ziel.iconset>\n".utf8))
    exit(1)
}
let out = URL(fileURLWithPath: args[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

// Zweiter Pfad (optional): Icons für den Home-Bildschirm auf dem Handy
if args.count > 2 {
    let webDir = URL(fileURLWithPath: args[2])
    for px in [180, 512] {
        guard let image = drawIcon(size: CGFloat(px)) else { exit(1) }
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = NSSize(width: px, height: px)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: webDir.appendingPathComponent("icon-\(px).png"))
        }
    }
}

for entry in sizes {
    guard let image = drawIcon(size: CGFloat(entry.px)) else { exit(1) }
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: entry.px, height: entry.px)
    guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
    try? png.write(to: out.appendingPathComponent(entry.name))
}
print("Icon erzeugt: \(out.path)")
