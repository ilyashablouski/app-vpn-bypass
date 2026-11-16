import AppKit

enum MenuIconState: CaseIterable {
    /// Исключения выключены: контур щита со стрелкой.
    case off
    /// Включены, но VPN не подключён: тот же контур, приглушённый.
    case waiting
    /// Исключения работают: сплошной щит, стрелка вырезана.
    case active
}

/// Ч/б (template) иконка для строки меню в стиле иконки приложения: щит со стрелкой-обходом.
/// Рисуется векторно, поэтому одинаково чёткая на любых экранах и в светлой/тёмной теме.
enum MenuBarIcon {
    private static var cache: [MenuIconState: NSImage] = [:]

    static func image(for state: MenuIconState) -> NSImage {
        if let cached = cache[state] { return cached }
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            draw(state, in: ctx)
            return true
        }
        img.isTemplate = true
        cache[state] = img
        return img
    }

    /// Те же координаты, что в make-icon.swift (холст 1024): щит занимает x 264...760, y 215...810.
    private static func draw(_ state: MenuIconState, in ctx: CGContext) {
        let shieldWidth: CGFloat = 496, shieldHeight: CGFloat = 595
        let s = 16 / shieldHeight
        ctx.translateBy(x: (18 - shieldWidth * s) / 2 - 264 * s, y: (18 - shieldHeight * s) / 2 - 215 * s)
        ctx.scaleBy(x: s, y: s)

        let shield = CGMutablePath()
        shield.move(to: CGPoint(x: 512, y: 810))
        shield.addCurve(to: CGPoint(x: 760, y: 720), control1: CGPoint(x: 590, y: 800), control2: CGPoint(x: 690, y: 760))
        shield.addLine(to: CGPoint(x: 760, y: 520))
        shield.addCurve(to: CGPoint(x: 512, y: 215), control1: CGPoint(x: 760, y: 360), control2: CGPoint(x: 620, y: 260))
        shield.addCurve(to: CGPoint(x: 264, y: 520), control1: CGPoint(x: 404, y: 260), control2: CGPoint(x: 264, y: 360))
        shield.addLine(to: CGPoint(x: 264, y: 720))
        shield.addCurve(to: CGPoint(x: 512, y: 810), control1: CGPoint(x: 334, y: 760), control2: CGPoint(x: 434, y: 800))
        shield.closeSubpath()

        let route = CGMutablePath()
        route.move(to: CGPoint(x: 390, y: 380))
        route.addCurve(to: CGPoint(x: 640, y: 640), control1: CGPoint(x: 390, y: 560), control2: CGPoint(x: 640, y: 460))

        let head = CGMutablePath()
        head.move(to: CGPoint(x: 640, y: 725))
        head.addLine(to: CGPoint(x: 568, y: 622))
        head.addLine(to: CGPoint(x: 712, y: 622))
        head.closeSubpath()

        let dot = CGRect(x: 350, y: 340, width: 80, height: 80)

        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setStrokeColor(.black)
        ctx.setFillColor(.black)

        // Группа с общей прозрачностью, чтобы части не накладывались друг на друга.
        ctx.setAlpha(state == .waiting ? 0.45 : 1)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        if state == .active {
            ctx.addPath(shield)
            ctx.fillPath()
        } else {
            ctx.setLineWidth(48)
            ctx.addPath(shield)
            ctx.strokePath()
        }

        // Стрелка одного размера во всех состояниях (уменьшена, чтобы не упираться в рамку).
        // В активном состоянии она вырезается из сплошного щита.
        ctx.translateBy(x: 512, y: 520)
        ctx.scaleBy(x: 0.74, y: 0.74)
        ctx.translateBy(x: -512, y: -530)
        if state == .active { ctx.setBlendMode(.clear) }
        ctx.setLineWidth(70)
        ctx.addPath(route)
        ctx.strokePath()
        ctx.addPath(head)
        ctx.fillPath()
        ctx.fillEllipse(in: dot.insetBy(dx: -10, dy: -10))
        ctx.endTransparencyLayer()
    }
}
