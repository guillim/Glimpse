// Glimpse/StarWarsCharacterGenerator.swift
import AppKit

/// Generates chibi Star Wars characters procedurally using Core Graphics.
/// Same architecture as CharacterGenerator — deterministic mapping from sessionID.
enum StarWarsCharacterGenerator {

    // MARK: - Character Definitions

    enum Character: Int, CaseIterable {
        case vader = 0
        case yoda
        case stormtrooper
        case r2d2
        case c3po
        case chewbacca
        case bobaFett
        case leia
    }

    /// Representative color for each character (used for menu bar dot).
    static func color(for sessionID: String) -> NSColor {
        let ch = character(for: sessionID)
        switch ch {
        case .vader:        return NSColor(red: 0.15, green: 0.15, blue: 0.20, alpha: 1)
        case .yoda:         return NSColor(red: 0.45, green: 0.65, blue: 0.30, alpha: 1)
        case .stormtrooper: return NSColor(red: 0.90, green: 0.90, blue: 0.92, alpha: 1)
        case .r2d2:         return NSColor(red: 0.30, green: 0.50, blue: 0.85, alpha: 1)
        case .c3po:         return NSColor(red: 0.85, green: 0.72, blue: 0.25, alpha: 1)
        case .chewbacca:    return NSColor(red: 0.55, green: 0.38, blue: 0.22, alpha: 1)
        case .bobaFett:     return NSColor(red: 0.35, green: 0.55, blue: 0.40, alpha: 1)
        case .leia:         return NSColor(red: 0.85, green: 0.75, blue: 0.65, alpha: 1)
        }
    }

    // MARK: - Cache

    private class CGImageBox {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    private static let cache = NSCache<NSString, CGImageBox>()

    // MARK: - Seeded RNG (same as CharacterGenerator)

    private static func seed(from sessionID: String) -> UInt64 {
        var hash: UInt64 = 5381
        for byte in sessionID.utf8 {
            hash = hash &* 33 &+ UInt64(byte)
        }
        return hash
    }

    static func character(for sessionID: String) -> Character {
        var s = seed(from: sessionID)
        s = s &* 6364136223846793005 &+ 1442695040888963407
        let roll = Int(s >> 33) % 10
        if roll < 3 { return Character(rawValue: 0)! }  // 30% star character
        return Character(rawValue: 1 + (roll - 3) % (Character.allCases.count - 1))!
    }

    // MARK: - Generate

    static func generate(sessionID: String, size: CGFloat) -> CGImage? {
        let ch = character(for: sessionID)
        let cacheKey = "\(ch.rawValue):\(Int(size.rounded()))" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached.image
        }

        let scale: CGFloat = 2.0
        guard let ctx = CGContext(
            data: nil,
            width: Int(size * scale),
            height: Int(size * scale),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: 0, y: -size * 0.1)

        switch ch {
        case .vader:        drawVader(ctx, size: size)
        case .yoda:         drawYoda(ctx, size: size)
        case .stormtrooper: drawStormtrooper(ctx, size: size)
        case .r2d2:         drawR2D2(ctx, size: size)
        case .c3po:         drawC3PO(ctx, size: size)
        case .chewbacca:    drawChewbacca(ctx, size: size)
        case .bobaFett:     drawBobaFett(ctx, size: size)
        case .leia:         drawLeia(ctx, size: size)
        }

        guard let image = ctx.makeImage() else { return nil }
        cache.setObject(CGImageBox(image), forKey: cacheKey)
        return image
    }

    // MARK: - Drawing Helpers

    private static let ol: CGFloat = 1.5  // base outline width

    private static func outlinedEllipse(_ ctx: CGContext, rect: CGRect, fill: CGColor, outline: CGFloat) {
        ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
        ctx.fillEllipse(in: rect.insetBy(dx: -outline, dy: -outline))
        ctx.setFillColor(fill)
        ctx.fillEllipse(in: rect)
    }

    private static func outlinedRect(_ ctx: CGContext, rect: CGRect, fill: CGColor, outline: CGFloat) {
        ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
        ctx.fill(rect.insetBy(dx: -outline, dy: -outline))
        ctx.setFillColor(fill)
        ctx.fill(rect)
    }

    private static func outlinedRoundRect(_ ctx: CGContext, rect: CGRect, fill: CGColor, outline: CGFloat, radius: CGFloat) {
        let outerPath = CGPath(roundedRect: rect.insetBy(dx: -outline, dy: -outline),
                               cornerWidth: radius + outline, cornerHeight: radius + outline, transform: nil)
        ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
        ctx.addPath(outerPath)
        ctx.fillPath()
        let innerPath = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        ctx.setFillColor(fill)
        ctx.addPath(innerPath)
        ctx.fillPath()
    }

    /// Draw a radial highlight on the head for depth.
    private static func headHighlight(_ ctx: CGContext, headRect: CGRect, cx: CGFloat, headY: CGFloat, headR: CGFloat) {
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                CGColor(gray: 1, alpha: 0.18),
                CGColor(gray: 1, alpha: 0.03),
                CGColor(gray: 0, alpha: 0.06)
            ] as CFArray,
            locations: [0, 0.5, 1]
        ) else { return }
        ctx.saveGState()
        ctx.addEllipse(in: headRect)
        ctx.clip()
        ctx.drawRadialGradient(gradient,
            startCenter: CGPoint(x: cx - headR * 0.25, y: headY + headR * 0.25),
            startRadius: 0,
            endCenter: CGPoint(x: cx, y: headY),
            endRadius: headR, options: [])
        ctx.restoreGState()
    }

    /// Simple chibi eyes — white sclera, dark pupil, highlight.
    private static func drawSimpleEyes(_ ctx: CGContext, cx: CGFloat, headY: CGFloat, headR: CGFloat, size s: CGFloat, spacing: CGFloat = 0.4) {
        let eyeY = headY - headR * 0.05
        let sp = headR * spacing
        let ew = headR * 0.26, eh = headR * 0.33

        for dir: CGFloat in [-1, 1] {
            let ex = cx + dir * sp
            // Dark socket
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex - ew - 1.5, y: eyeY - eh - 1.5, width: (ew + 1.5) * 2, height: (eh + 1.5) * 2))
            // White sclera
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex - ew, y: eyeY - eh, width: ew * 2, height: eh * 2))
            // Dark pupil
            let pw = ew * 0.55, ph = eh * 0.55
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex - pw, y: eyeY - ph, width: pw * 2, height: ph * 2))
            // Highlight
            let hlR = ew * 0.28
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex + ew * 0.2 - hlR / 2, y: eyeY + eh * 0.25 - hlR / 2, width: hlR, height: hlR))
        }
    }

    /// Simple smile mouth.
    private static func drawSmile(_ ctx: CGContext, cx: CGFloat, headY: CGFloat, headR: CGFloat, size s: CGFloat) {
        let mouthY = headY - headR * 0.4
        ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
        ctx.setLineWidth(max(s * 0.018, 1.2))
        ctx.setLineCap(.round)
        ctx.addArc(center: CGPoint(x: cx, y: mouthY + headR * 0.1),
                   radius: headR * 0.15,
                   startAngle: -.pi * 0.15,
                   endAngle: -.pi * 0.85,
                   clockwise: true)
        ctx.strokePath()
        ctx.setLineCap(.butt)
    }

    /// Drop shadow ellipse beneath character.
    private static func drawShadow(_ ctx: CGContext, cx: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) {
        ctx.setFillColor(CGColor(gray: 0, alpha: 0.2))
        ctx.fillEllipse(in: CGRect(x: cx - w / 2, y: y, width: w, height: h))
    }

    /// Stubby chibi feet.
    private static func drawFeet(_ ctx: CGContext, cx: CGFloat, footY: CGFloat, bodyW: CGFloat, fill: CGColor, size s: CGFloat) {
        for dir: CGFloat in [-1, 1] {
            let fx = cx + dir * bodyW * 0.35
            let footRect = CGRect(x: fx - s * 0.045, y: footY - s * 0.025, width: s * 0.09, height: s * 0.05)
            outlinedEllipse(ctx, rect: footRect, fill: fill, outline: ol)
        }
    }

    /// Stubby chibi arms.
    private static func drawArms(_ ctx: CGContext, cx: CGFloat, bodyY: CGFloat, bodyW: CGFloat, bodyH: CGFloat, fill: CGColor, size s: CGFloat) {
        for dir: CGFloat in [-1, 1] {
            let ax = cx + dir * (bodyW / 2 + s * 0.04)
            let ay = bodyY + bodyH * 0.05
            ctx.saveGState()
            ctx.translateBy(x: ax, y: ay)
            ctx.rotate(by: dir * 0.3)
            let armRect = CGRect(x: -s * 0.03, y: -s * 0.055, width: s * 0.06, height: s * 0.11)
            outlinedEllipse(ctx, rect: armRect, fill: fill, outline: ol)
            ctx.restoreGState()
        }
    }

    // MARK: - Darth Vader

    private static func drawVader(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2
        let headR = s * 0.32
        let headY = s * 0.62
        let bodyW = s * 0.32, bodyH = s * 0.24
        let bodyY = s * 0.25

        let black = CGColor(gray: 0.12, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW, h: s * 0.04)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: black, size: s)

        // Cape — wide dark triangle behind body
        ctx.setFillColor(CGColor(gray: 0.08, alpha: 1))
        ctx.move(to: CGPoint(x: cx - bodyW * 0.8, y: bodyY - bodyH / 2 - s * 0.02))
        ctx.addLine(to: CGPoint(x: cx + bodyW * 0.8, y: bodyY - bodyH / 2 - s * 0.02))
        ctx.addLine(to: CGPoint(x: cx, y: bodyY + bodyH * 0.6))
        ctx.fillPath()

        // Body
        let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH)
        outlinedEllipse(ctx, rect: bodyRect, fill: black, outline: ol)

        // Chest panel — small gray rectangle on chest
        let panelW = bodyW * 0.3, panelH = bodyH * 0.35
        outlinedRect(ctx, rect: CGRect(x: cx - panelW / 2, y: bodyY - panelH / 2, width: panelW, height: panelH),
                     fill: CGColor(gray: 0.25, alpha: 1), outline: ol * 0.5)
        // Colored buttons on panel
        let btnR = s * 0.012
        for (i, color) in [CGColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1),
                            CGColor(red: 0.2, green: 0.7, blue: 0.2, alpha: 1),
                            CGColor(red: 0.3, green: 0.5, blue: 0.9, alpha: 1)].enumerated() {
            let bx = cx - panelW * 0.2 + CGFloat(i) * panelW * 0.2
            ctx.setFillColor(color)
            ctx.fillEllipse(in: CGRect(x: bx - btnR, y: bodyY - btnR, width: btnR * 2, height: btnR * 2))
        }

        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: black, size: s)

        // Helmet — head
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: black, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // Helmet dome ridge — arc across top
        ctx.setStrokeColor(CGColor(gray: 0.25, alpha: 1))
        ctx.setLineWidth(s * 0.015)
        ctx.addArc(center: CGPoint(x: cx, y: headY), radius: headR * 0.85,
                   startAngle: .pi * 0.15, endAngle: .pi * 0.85, clockwise: false)
        ctx.strokePath()

        // Face plate — darker triangular area
        ctx.setFillColor(CGColor(gray: 0.08, alpha: 1))
        let faceTop = headY + headR * 0.1
        let faceBot = headY - headR * 0.65
        ctx.move(to: CGPoint(x: cx - headR * 0.5, y: faceTop))
        ctx.addLine(to: CGPoint(x: cx + headR * 0.5, y: faceTop))
        ctx.addLine(to: CGPoint(x: cx + headR * 0.15, y: faceBot))
        ctx.addLine(to: CGPoint(x: cx - headR * 0.15, y: faceBot))
        ctx.fillPath()

        // Red eye slit — menacing horizontal line
        ctx.setStrokeColor(CGColor(red: 0.9, green: 0.15, blue: 0.15, alpha: 0.9))
        ctx.setLineWidth(s * 0.018)
        let eyeSlitY = headY - headR * 0.05
        ctx.move(to: CGPoint(x: cx - headR * 0.3, y: eyeSlitY))
        ctx.addLine(to: CGPoint(x: cx + headR * 0.3, y: eyeSlitY))
        ctx.strokePath()

        // Mouth grille — horizontal lines
        ctx.setStrokeColor(CGColor(gray: 0.25, alpha: 0.7))
        ctx.setLineWidth(s * 0.008)
        for i in 1...3 {
            let my = headY - headR * 0.25 - CGFloat(i) * headR * 0.1
            let hw = headR * (0.2 - CGFloat(i) * 0.03)
            ctx.move(to: CGPoint(x: cx - hw, y: my))
            ctx.addLine(to: CGPoint(x: cx + hw, y: my))
        }
        ctx.strokePath()
    }

    // MARK: - Yoda

    private static func drawYoda(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2
        let headR = s * 0.30
        let headY = s * 0.60
        let bodyW = s * 0.24, bodyH = s * 0.20
        let bodyY = s * 0.27

        let green = CGColor(red: 0.45, green: 0.62, blue: 0.30, alpha: 1)
        let lightGreen = CGColor(red: 0.55, green: 0.72, blue: 0.40, alpha: 1)
        let robe = CGColor(red: 0.42, green: 0.35, blue: 0.25, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW * 0.8, h: s * 0.035)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: green, size: s)

        // Body (robe)
        let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH)
        outlinedEllipse(ctx, rect: bodyRect, fill: robe, outline: ol)

        // Robe collar
        let collarRect = CGRect(x: cx - bodyW * 0.25, y: bodyY + bodyH * 0.15, width: bodyW * 0.5, height: bodyH * 0.3)
        outlinedEllipse(ctx, rect: collarRect, fill: CGColor(red: 0.48, green: 0.40, blue: 0.30, alpha: 1), outline: ol * 0.5)

        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: robe, size: s)

        // Huge pointy ears — behind head, very wide
        for dir: CGFloat in [-1, 1] {
            let earBaseX = cx + dir * headR * 0.7
            let earTipX = cx + dir * (headR + s * 0.22)
            let earBaseY = headY

            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.saveGState()
            ctx.move(to: CGPoint(x: earBaseX, y: earBaseY + headR * 0.15 + ol))
            ctx.addLine(to: CGPoint(x: earTipX + dir * ol, y: earBaseY))
            ctx.addLine(to: CGPoint(x: earBaseX, y: earBaseY - headR * 0.15 - ol))
            ctx.fillPath()
            ctx.restoreGState()

            ctx.setFillColor(green)
            ctx.move(to: CGPoint(x: earBaseX, y: earBaseY + headR * 0.13))
            ctx.addLine(to: CGPoint(x: earTipX, y: earBaseY))
            ctx.addLine(to: CGPoint(x: earBaseX, y: earBaseY - headR * 0.13))
            ctx.fillPath()

            // Inner ear
            ctx.setFillColor(lightGreen)
            ctx.move(to: CGPoint(x: earBaseX + dir * headR * 0.05, y: earBaseY + headR * 0.06))
            ctx.addLine(to: CGPoint(x: earTipX - dir * s * 0.04, y: earBaseY))
            ctx.addLine(to: CGPoint(x: earBaseX + dir * headR * 0.05, y: earBaseY - headR * 0.06))
            ctx.fillPath()
        }

        // Head
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: green, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // Wrinkles on forehead
        ctx.setStrokeColor(CGColor(red: 0.35, green: 0.50, blue: 0.22, alpha: 0.5))
        ctx.setLineWidth(s * 0.008)
        for i in 0..<3 {
            let wy = headY + headR * 0.25 + CGFloat(i) * headR * 0.12
            ctx.move(to: CGPoint(x: cx - headR * 0.3, y: wy))
            ctx.addLine(to: CGPoint(x: cx + headR * 0.3, y: wy))
        }
        ctx.strokePath()

        // Eyes — slightly squinted
        drawSimpleEyes(ctx, cx: cx, headY: headY, headR: headR, size: s, spacing: 0.35)
        drawSmile(ctx, cx: cx, headY: headY, headR: headR, size: s)
    }

    // MARK: - Stormtrooper

    private static func drawStormtrooper(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2
        let headR = s * 0.32
        let headY = s * 0.62
        let bodyW = s * 0.28, bodyH = s * 0.22
        let bodyY = s * 0.25

        let white = CGColor(gray: 0.95, alpha: 1)
        let darkArmor = CGColor(gray: 0.15, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW, h: s * 0.04)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: white, size: s)

        // Body
        let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH)
        outlinedEllipse(ctx, rect: bodyRect, fill: white, outline: ol)

        // Armor detail — black center line
        ctx.setStrokeColor(darkArmor)
        ctx.setLineWidth(s * 0.012)
        ctx.move(to: CGPoint(x: cx, y: bodyY + bodyH * 0.35))
        ctx.addLine(to: CGPoint(x: cx, y: bodyY - bodyH * 0.35))
        ctx.strokePath()

        // Belly plate
        let bellyRect = CGRect(x: cx - bodyW * 0.18, y: bodyY - bodyH * 0.2, width: bodyW * 0.36, height: bodyH * 0.3)
        outlinedRect(ctx, rect: bellyRect, fill: CGColor(gray: 0.85, alpha: 1), outline: ol * 0.5)

        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: white, size: s)

        // Helmet
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: white, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // Visor — two dark angled eye shapes connected by a bridge
        let visorY = headY - headR * 0.05
        ctx.setFillColor(darkArmor)
        for dir: CGFloat in [-1, 1] {
            let vx = cx + dir * headR * 0.3
            // Angled eye slot
            ctx.saveGState()
            ctx.translateBy(x: vx, y: visorY)
            ctx.rotate(by: dir * 0.15)
            let vw = headR * 0.28, vh = headR * 0.18
            ctx.fillEllipse(in: CGRect(x: -vw, y: -vh, width: vw * 2, height: vh * 2))
            ctx.restoreGState()
        }

        // Bridge between eyes
        ctx.setFillColor(darkArmor)
        ctx.fill(CGRect(x: cx - headR * 0.08, y: visorY - headR * 0.05, width: headR * 0.16, height: headR * 0.1))

        // Mouth — vertical dark vent area
        let ventY = headY - headR * 0.45
        let ventW = headR * 0.15, ventH = headR * 0.2
        outlinedRoundRect(ctx, rect: CGRect(x: cx - ventW, y: ventY - ventH, width: ventW * 2, height: ventH * 2),
                          fill: darkArmor, outline: ol * 0.5, radius: s * 0.01)

        // Cheek vents — small horizontal lines
        ctx.setStrokeColor(CGColor(gray: 0.7, alpha: 1))
        ctx.setLineWidth(s * 0.006)
        for dir: CGFloat in [-1, 1] {
            for i in 0..<2 {
                let lx = cx + dir * headR * 0.45
                let ly = headY - headR * 0.3 - CGFloat(i) * headR * 0.08
                ctx.move(to: CGPoint(x: lx - headR * 0.08, y: ly))
                ctx.addLine(to: CGPoint(x: lx + headR * 0.08, y: ly))
            }
        }
        ctx.strokePath()
    }

    // MARK: - R2-D2

    private static func drawR2D2(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2
        let bodyW = s * 0.32, bodyH = s * 0.32
        let bodyY = s * 0.35
        let headR = s * 0.22
        let headY = s * 0.62

        let white = CGColor(gray: 0.92, alpha: 1)
        let blue = CGColor(red: 0.25, green: 0.45, blue: 0.82, alpha: 1)
        let silver = CGColor(gray: 0.75, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.06, w: bodyW * 1.1, h: s * 0.04)

        // Side legs
        for dir: CGFloat in [-1, 1] {
            let legX = cx + dir * bodyW * 0.5
            let legW = s * 0.06, legH = bodyH * 0.7
            outlinedRect(ctx, rect: CGRect(x: legX - legW / 2, y: bodyY - legH / 2 - bodyH * 0.1, width: legW, height: legH),
                         fill: white, outline: ol)
            // Foot
            outlinedRoundRect(ctx, rect: CGRect(x: legX - legW * 0.7, y: bodyY - bodyH / 2 - s * 0.06, width: legW * 1.4, height: s * 0.05),
                              fill: blue, outline: ol, radius: s * 0.01)
        }

        // Center leg
        outlinedRect(ctx, rect: CGRect(x: cx - s * 0.025, y: bodyY - bodyH / 2 - s * 0.04, width: s * 0.05, height: s * 0.08),
                     fill: white, outline: ol)
        outlinedRoundRect(ctx, rect: CGRect(x: cx - s * 0.035, y: bodyY - bodyH / 2 - s * 0.06, width: s * 0.07, height: s * 0.04),
                          fill: silver, outline: ol, radius: s * 0.008)

        // Body — cylindrical (rounded rect)
        outlinedRoundRect(ctx, rect: CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH),
                          fill: white, outline: ol, radius: s * 0.03)

        // Blue panels on body
        let panelH = bodyH * 0.25
        outlinedRect(ctx, rect: CGRect(x: cx - bodyW * 0.4, y: bodyY + bodyH * 0.05, width: bodyW * 0.8, height: panelH),
                     fill: blue, outline: ol * 0.5)
        outlinedRect(ctx, rect: CGRect(x: cx - bodyW * 0.35, y: bodyY - bodyH * 0.3, width: bodyW * 0.7, height: panelH * 0.6),
                     fill: blue, outline: ol * 0.5)

        // Dome — semicircle on top
        let domeRect = CGRect(x: cx - headR, y: headY - headR * 0.3, width: headR * 2, height: headR * 1.6)
        outlinedEllipse(ctx, rect: domeRect, fill: silver, outline: ol)
        headHighlight(ctx, headRect: domeRect, cx: cx, headY: headY + headR * 0.3, headR: headR)

        // Blue dome panel
        ctx.saveGState()
        ctx.addEllipse(in: domeRect)
        ctx.clip()
        ctx.setFillColor(blue)
        ctx.fill(CGRect(x: cx - headR * 0.5, y: headY, width: headR, height: headR * 0.5))
        ctx.restoreGState()

        // Main eye — red/dark lens
        let eyeR = headR * 0.2
        let eyeY = headY + headR * 0.15
        outlinedEllipse(ctx, rect: CGRect(x: cx - eyeR, y: eyeY - eyeR, width: eyeR * 2, height: eyeR * 2),
                         fill: CGColor(gray: 0.15, alpha: 1), outline: ol)
        // Red glow
        ctx.setFillColor(CGColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 0.8))
        let glowR = eyeR * 0.5
        ctx.fillEllipse(in: CGRect(x: cx - glowR, y: eyeY - glowR, width: glowR * 2, height: glowR * 2))
        // Highlight
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.6))
        let hlR = eyeR * 0.25
        ctx.fillEllipse(in: CGRect(x: cx + eyeR * 0.2, y: eyeY + eyeR * 0.2, width: hlR, height: hlR))
    }

    // MARK: - C-3PO

    private static func drawC3PO(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2
        let headR = s * 0.30
        let headY = s * 0.62
        let bodyW = s * 0.26, bodyH = s * 0.22
        let bodyY = s * 0.25

        let gold = CGColor(red: 0.82, green: 0.70, blue: 0.22, alpha: 1)
        let darkGold = CGColor(red: 0.65, green: 0.55, blue: 0.18, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW, h: s * 0.04)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: gold, size: s)

        // Body
        let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH)
        outlinedEllipse(ctx, rect: bodyRect, fill: gold, outline: ol)

        // Torso plating lines
        ctx.setStrokeColor(darkGold)
        ctx.setLineWidth(s * 0.008)
        ctx.move(to: CGPoint(x: cx, y: bodyY + bodyH * 0.3))
        ctx.addLine(to: CGPoint(x: cx, y: bodyY - bodyH * 0.3))
        ctx.strokePath()

        // Belly details
        let wires = CGColor(red: 0.50, green: 0.50, blue: 0.55, alpha: 1)
        let wireRect = CGRect(x: cx - bodyW * 0.15, y: bodyY - bodyH * 0.15, width: bodyW * 0.3, height: bodyH * 0.25)
        outlinedRect(ctx, rect: wireRect, fill: wires, outline: ol * 0.5)

        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: gold, size: s)

        // Head — slightly elongated vertically
        let headW = headR * 0.9
        let headRect = CGRect(x: cx - headW, y: headY - headR, width: headW * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: gold, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // Eyes — large round, worried look
        let eyeY = headY
        for dir: CGFloat in [-1, 1] {
            let ex = cx + dir * headW * 0.38
            let er = headR * 0.22
            // Dark socket
            outlinedEllipse(ctx, rect: CGRect(x: ex - er, y: eyeY - er, width: er * 2, height: er * 2),
                            fill: CGColor(gray: 0.12, alpha: 1), outline: ol)
            // Yellow glow ring
            ctx.setStrokeColor(CGColor(red: 0.95, green: 0.85, blue: 0.30, alpha: 0.8))
            ctx.setLineWidth(s * 0.012)
            ctx.addEllipse(in: CGRect(x: ex - er * 0.7, y: eyeY - er * 0.7, width: er * 1.4, height: er * 1.4))
            ctx.strokePath()
        }

        // Mouth plate — horizontal line
        ctx.setStrokeColor(darkGold)
        ctx.setLineWidth(s * 0.012)
        let mouthY = headY - headR * 0.38
        ctx.move(to: CGPoint(x: cx - headW * 0.25, y: mouthY))
        ctx.addLine(to: CGPoint(x: cx + headW * 0.25, y: mouthY))
        ctx.strokePath()

        // Forehead ridge
        ctx.setStrokeColor(darkGold)
        ctx.setLineWidth(s * 0.008)
        ctx.addArc(center: CGPoint(x: cx, y: headY), radius: headR * 0.7,
                   startAngle: .pi * 0.2, endAngle: .pi * 0.8, clockwise: false)
        ctx.strokePath()
    }

    // MARK: - Chewbacca

    private static func drawChewbacca(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2
        let headR = s * 0.33
        let headY = s * 0.62
        let bodyW = s * 0.30, bodyH = s * 0.24
        let bodyY = s * 0.25

        let brown = CGColor(red: 0.50, green: 0.35, blue: 0.20, alpha: 1)
        let lightBrown = CGColor(red: 0.62, green: 0.48, blue: 0.30, alpha: 1)
        let darkBrown = CGColor(red: 0.35, green: 0.22, blue: 0.12, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW * 1.1, h: s * 0.04)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: brown, size: s)

        // Body
        let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH)
        outlinedEllipse(ctx, rect: bodyRect, fill: brown, outline: ol)

        // Bandolier — diagonal stripe
        ctx.setStrokeColor(CGColor(red: 0.30, green: 0.25, blue: 0.18, alpha: 1))
        ctx.setLineWidth(s * 0.025)
        ctx.move(to: CGPoint(x: cx - bodyW * 0.35, y: bodyY - bodyH * 0.3))
        ctx.addLine(to: CGPoint(x: cx + bodyW * 0.25, y: bodyY + bodyH * 0.4))
        ctx.strokePath()

        // Fur texture on body — short strokes
        ctx.setStrokeColor(lightBrown)
        ctx.setLineWidth(s * 0.006)
        for i in 0..<6 {
            let fx = cx - bodyW * 0.3 + CGFloat(i) * bodyW * 0.12
            let fy = bodyY - bodyH * 0.1 + CGFloat(i % 3) * bodyH * 0.1
            ctx.move(to: CGPoint(x: fx, y: fy))
            ctx.addLine(to: CGPoint(x: fx + s * 0.01, y: fy + s * 0.02))
        }
        ctx.strokePath()

        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: brown, size: s)

        // Head — slightly larger, furry
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: brown, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // Fur tufts on top of head
        ctx.setStrokeColor(lightBrown)
        ctx.setLineWidth(s * 0.01)
        ctx.setLineCap(.round)
        for i in -2...2 {
            let tx = cx + CGFloat(i) * headR * 0.2
            let ty = headY + headR * 0.85
            ctx.move(to: CGPoint(x: tx, y: ty))
            ctx.addLine(to: CGPoint(x: tx + CGFloat(i) * s * 0.01, y: ty + s * 0.04))
        }
        ctx.strokePath()
        ctx.setLineCap(.butt)

        // Lighter face area
        let faceRect = CGRect(x: cx - headR * 0.45, y: headY - headR * 0.55, width: headR * 0.9, height: headR * 0.8)
        outlinedEllipse(ctx, rect: faceRect, fill: lightBrown, outline: ol * 0.5)

        // Eyes
        drawSimpleEyes(ctx, cx: cx, headY: headY, headR: headR, size: s, spacing: 0.3)

        // Nose
        ctx.setFillColor(darkBrown)
        let noseR = headR * 0.08
        ctx.fillEllipse(in: CGRect(x: cx - noseR, y: headY - headR * 0.25 - noseR, width: noseR * 2, height: noseR * 2))

        // Mouth — open roar
        ctx.setFillColor(CGColor(red: 0.25, green: 0.15, blue: 0.08, alpha: 1))
        let mouthW = headR * 0.25, mouthH = headR * 0.12
        ctx.fillEllipse(in: CGRect(x: cx - mouthW, y: headY - headR * 0.42, width: mouthW * 2, height: mouthH * 2))
    }

    // MARK: - Boba Fett

    private static func drawBobaFett(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2
        let headR = s * 0.32
        let headY = s * 0.62
        let bodyW = s * 0.28, bodyH = s * 0.22
        let bodyY = s * 0.25

        let green = CGColor(red: 0.35, green: 0.52, blue: 0.38, alpha: 1)
        let red = CGColor(red: 0.65, green: 0.22, blue: 0.18, alpha: 1)
        let gray = CGColor(gray: 0.55, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW, h: s * 0.04)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: green, size: s)

        // Jetpack — behind body
        let jpW = s * 0.06, jpH = bodyH * 0.8
        outlinedRoundRect(ctx, rect: CGRect(x: cx + bodyW * 0.35, y: bodyY - jpH / 2, width: jpW, height: jpH),
                          fill: gray, outline: ol, radius: s * 0.01)

        // Body (armor)
        let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH)
        outlinedEllipse(ctx, rect: bodyRect, fill: green, outline: ol)

        // Chest armor plates
        let plateW = bodyW * 0.2, plateH = bodyH * 0.35
        for dir: CGFloat in [-1, 1] {
            outlinedRect(ctx, rect: CGRect(x: cx + dir * bodyW * 0.12 - plateW / 2, y: bodyY, width: plateW, height: plateH),
                         fill: red, outline: ol * 0.5)
        }

        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: green, size: s)

        // Helmet
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: green, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // T-visor — dark T shape
        ctx.setFillColor(CGColor(gray: 0.1, alpha: 0.9))
        let visorY = headY + headR * 0.05
        // Horizontal bar
        ctx.fill(CGRect(x: cx - headR * 0.55, y: visorY - headR * 0.08, width: headR * 1.1, height: headR * 0.16))
        // Vertical bar
        ctx.fill(CGRect(x: cx - headR * 0.07, y: visorY - headR * 0.45, width: headR * 0.14, height: headR * 0.37))

        // Antenna — small stalk on right side of helmet
        ctx.setStrokeColor(CGColor(gray: 0.4, alpha: 1))
        ctx.setLineWidth(s * 0.015)
        let antX = cx + headR * 0.75
        let antBaseY = headY + headR * 0.5
        ctx.move(to: CGPoint(x: antX, y: antBaseY))
        ctx.addLine(to: CGPoint(x: antX + s * 0.02, y: antBaseY + s * 0.08))
        ctx.strokePath()

        // Range finder tip
        ctx.setFillColor(CGColor(red: 0.9, green: 0.3, blue: 0.2, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: antX + s * 0.01, y: antBaseY + s * 0.07, width: s * 0.025, height: s * 0.025))

        // Helmet dent/scratch — dark line
        ctx.setStrokeColor(CGColor(red: 0.3, green: 0.42, blue: 0.32, alpha: 0.6))
        ctx.setLineWidth(s * 0.006)
        ctx.move(to: CGPoint(x: cx - headR * 0.3, y: headY + headR * 0.55))
        ctx.addLine(to: CGPoint(x: cx - headR * 0.1, y: headY + headR * 0.4))
        ctx.strokePath()
    }

    // MARK: - Princess Leia

    private static func drawLeia(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2
        let headR = s * 0.30
        let headY = s * 0.60
        let bodyW = s * 0.26, bodyH = s * 0.20
        let bodyY = s * 0.25

        let white = CGColor(gray: 0.95, alpha: 1)
        let skin = CGColor(red: 0.90, green: 0.78, blue: 0.68, alpha: 1)
        let hairBrown = CGColor(red: 0.30, green: 0.20, blue: 0.12, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW, h: s * 0.04)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: white, size: s)

        // Body — white dress
        let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH)
        outlinedEllipse(ctx, rect: bodyRect, fill: white, outline: ol)

        // Belt
        let beltH = bodyH * 0.12
        outlinedRect(ctx, rect: CGRect(x: cx - bodyW * 0.4, y: bodyY - beltH / 2, width: bodyW * 0.8, height: beltH),
                     fill: CGColor(gray: 0.7, alpha: 1), outline: ol * 0.5)

        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: white, size: s)

        // Hair buns — two circles on sides of head (drawn before head)
        let bunR = headR * 0.35
        for dir: CGFloat in [-1, 1] {
            let bunX = cx + dir * (headR + bunR * 0.3)
            let bunY = headY + headR * 0.1

            // Dark outline
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: bunX - bunR - ol, y: bunY - bunR - ol, width: (bunR + ol) * 2, height: (bunR + ol) * 2))
            // Bun fill
            ctx.setFillColor(hairBrown)
            ctx.fillEllipse(in: CGRect(x: bunX - bunR, y: bunY - bunR, width: bunR * 2, height: bunR * 2))

            // Spiral detail on bun
            ctx.setStrokeColor(CGColor(red: 0.22, green: 0.14, blue: 0.08, alpha: 0.6))
            ctx.setLineWidth(s * 0.006)
            ctx.addArc(center: CGPoint(x: bunX, y: bunY), radius: bunR * 0.5,
                       startAngle: 0, endAngle: .pi * 1.5, clockwise: false)
            ctx.strokePath()
        }

        // Head
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: skin, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // Hair on top of head — dark cap
        ctx.saveGState()
        ctx.addEllipse(in: headRect)
        ctx.clip()
        ctx.setFillColor(hairBrown)
        ctx.fill(CGRect(x: cx - headR, y: headY + headR * 0.2, width: headR * 2, height: headR * 0.9))
        ctx.restoreGState()

        // Center part line in hair
        ctx.setStrokeColor(CGColor(red: 0.22, green: 0.14, blue: 0.08, alpha: 0.5))
        ctx.setLineWidth(s * 0.008)
        ctx.move(to: CGPoint(x: cx, y: headY + headR * 0.95))
        ctx.addLine(to: CGPoint(x: cx, y: headY + headR * 0.2))
        ctx.strokePath()

        // Eyes and mouth
        drawSimpleEyes(ctx, cx: cx, headY: headY, headR: headR, size: s, spacing: 0.38)
        drawSmile(ctx, cx: cx, headY: headY, headR: headR, size: s)

        // Rosy cheeks
        ctx.setFillColor(CGColor(red: 0.95, green: 0.60, blue: 0.55, alpha: 0.3))
        let cheekR = headR * 0.12
        for dir: CGFloat in [-1, 1] {
            let chx = cx + dir * headR * 0.5
            ctx.fillEllipse(in: CGRect(x: chx - cheekR, y: headY - headR * 0.25, width: cheekR * 2, height: cheekR * 2))
        }
    }
}
