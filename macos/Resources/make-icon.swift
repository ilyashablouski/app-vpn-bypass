#!/usr/bin/env swift
// Генерирует AppIcon.icns: щит с изогнутой стрелкой (обход VPN) на градиентном фоне.
//   swift Resources/make-icon.swift Resources/AppIcon.icns
import AppKit

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.icns"
let cs = CGColorSpaceCreateDeviceRGB()

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [r, g, b, a])!
}

/// Рисует иконку в координатах 1024x1024 (начало внизу слева).
func draw(in ctx: CGContext) {
    let bodyRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let body = CGPath(roundedRect: bodyRect, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Фон (без внешней тени).
    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    let bg = CGGradient(colorsSpace: cs, colors: [color(0.12, 0.78, 0.92), color(0.36, 0.22, 0.88)] as CFArray,
                        locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 100, y: 924), end: CGPoint(x: 924, y: 100), options: [])
    // Мягкий блик сверху.
    let gloss = CGGradient(colorsSpace: cs, colors: [color(1, 1, 1, 0.28), color(1, 1, 1, 0)] as CFArray,
                           locations: [0, 1])!
    ctx.drawLinearGradient(gloss, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 560), options: [])
    ctx.restoreGState()

    // Щит.
    let shield = CGMutablePath()
    shield.move(to: CGPoint(x: 512, y: 810))
    shield.addCurve(to: CGPoint(x: 760, y: 720), control1: CGPoint(x: 590, y: 800), control2: CGPoint(x: 690, y: 760))
    shield.addLine(to: CGPoint(x: 760, y: 520))
    shield.addCurve(to: CGPoint(x: 512, y: 215), control1: CGPoint(x: 760, y: 360), control2: CGPoint(x: 620, y: 260))
    shield.addCurve(to: CGPoint(x: 264, y: 520), control1: CGPoint(x: 404, y: 260), control2: CGPoint(x: 264, y: 360))
    shield.addLine(to: CGPoint(x: 264, y: 720))
    shield.addCurve(to: CGPoint(x: 512, y: 810), control1: CGPoint(x: 334, y: 760), control2: CGPoint(x: 434, y: 800))
    shield.closeSubpath()

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 22, color: color(0.05, 0.05, 0.3, 0.35))
    ctx.addPath(shield)
    ctx.setFillColor(color(1, 1, 1, 0.97))
    ctx.fillPath()
    ctx.restoreGState()

    // Стрелка-обход внутри щита (цвета фона).
    let ink = color(0.22, 0.42, 0.95)
    ctx.setStrokeColor(ink)
    ctx.setFillColor(ink)
    ctx.setLineWidth(48)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    let route = CGMutablePath()
    route.move(to: CGPoint(x: 390, y: 380))
    route.addCurve(to: CGPoint(x: 640, y: 640), control1: CGPoint(x: 390, y: 560), control2: CGPoint(x: 640, y: 460))
    ctx.addPath(route)
    ctx.strokePath()

    let head = CGMutablePath()
    head.move(to: CGPoint(x: 640, y: 725))
    head.addLine(to: CGPoint(x: 568, y: 622))
    head.addLine(to: CGPoint(x: 712, y: 622))
    head.closeSubpath()
    ctx.addPath(head)
    ctx.fillPath()

    ctx.fillEllipse(in: CGRect(x: 390 - 40, y: 380 - 40, width: 80, height: 80))
}

func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gc
    let ctx = gc.cgContext
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    draw(in: ctx)
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = fm.temporaryDirectory.appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try png(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try png(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", outPath]
try p.run()
p.waitUntilExit()
try? fm.removeItem(at: iconset)
exit(p.terminationStatus)
