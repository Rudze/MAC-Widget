// Génère l'icône : carré sombre avec quatre tuiles blanches.
import AppKit

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.1
    let body = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)
    NSGradient(starting: NSColor(white: 0.22, alpha: 1), ending: NSColor(white: 0.04, alpha: 1))!.draw(in: path, angle: -90)
    let gap = body.width * 0.07, pad = body.width * 0.17
    let tile = (body.width - 2 * pad - gap) / 2
    let alphas: [CGFloat] = [1, 0.55, 0.55, 0.28]
    for i in 0..<4 {
        let x = body.minX + pad + CGFloat(i % 2) * (tile + gap)
        let y = body.maxY - pad - tile - CGFloat(i / 2) * (tile + gap)
        NSColor(white: 1, alpha: alphas[i]).setFill()
        NSBezierPath(roundedRect: NSRect(x: x, y: y, width: tile, height: tile), xRadius: tile * 0.28, yRadius: tile * 0.28).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base)@2x.png"))
}
