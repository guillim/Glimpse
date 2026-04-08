// Glimpse/MarvelCharacterGenerator.swift
import AppKit

/// Generates chibi Marvel superhero characters procedurally using Core Graphics.
/// Same architecture as StarWarsCharacterGenerator — deterministic mapping from sessionID.
enum MarvelCharacterGenerator {

    // MARK: - Character Definitions

    enum Character: Int, CaseIterable {
        case ironMan = 0
        case spiderMan
        case captainAmerica
        case thor
        case hulk
        case blackWidow
        case blackPanther
        case wolverine
    }

    /// Representative color for each character (used for menu bar dot).
    static func color(for sessionID: String) -> NSColor {
        let ch = character(for: sessionID)
        switch ch {
        case .ironMan:          return NSColor(red: 0.80, green: 0.15, blue: 0.15, alpha: 1)
        case .spiderMan:        return NSColor(red: 0.85, green: 0.10, blue: 0.10, alpha: 1)
        case .captainAmerica:   return NSColor(red: 0.20, green: 0.35, blue: 0.70, alpha: 1)
        case .thor:             return NSColor(red: 0.75, green: 0.20, blue: 0.20, alpha: 1)
        case .hulk:             return NSColor(red: 0.25, green: 0.65, blue: 0.20, alpha: 1)
        case .blackWidow:       return NSColor(red: 0.70, green: 0.20, blue: 0.15, alpha: 1)
        case .blackPanther:     return NSColor(red: 0.20, green: 0.15, blue: 0.25, alpha: 1)
        case .wolverine:        return NSColor(red: 0.90, green: 0.80, blue: 0.15, alpha: 1)
        }
    }

    // MARK: - Cache

    private class CGImageBox {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    private static let cache = NSCache<NSString, CGImageBox>()

    // MARK: - Character Assignment (dedup across sessions)

    private static var assignments: [String: Character] = [:]

    static func releaseAssignment(for sessionID: String) {
        assignments.removeValue(forKey: sessionID)
    }

    // MARK: - Seeded RNG (same as CharacterGenerator)

    private static func seed(from sessionID: String) -> UInt64 {
        var hash: UInt64 = 5381
        for byte in sessionID.utf8 {
            hash = hash &* 33 &+ UInt64(byte)
        }
        return hash
    }

    private static func preferredCharacter(for sessionID: String) -> Character {
        var s = seed(from: sessionID)
        s = s &* 6364136223846793005 &+ 1442695040888963407
        let roll = Int(s >> 33) % 10
        if roll < 9 { return Character(rawValue: 0)! }  // 90% star character
        return Character(rawValue: 1 + (roll - 9) % (Character.allCases.count - 1))!
    }

    static func character(for sessionID: String) -> Character {
        if let existing = assignments[sessionID] { return existing }
        let preferred = preferredCharacter(for: sessionID)
        let usedRawValues = Set(assignments.values.map(\.rawValue))
        let result: Character
        if !usedRawValues.contains(preferred.rawValue) {
            result = preferred
        } else if let unused = Character.allCases.first(where: { !usedRawValues.contains($0.rawValue) }) {
            result = unused
        } else {
            result = preferred
        }
        assignments[sessionID] = result
        return result
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
        case .ironMan:          drawIronMan(ctx, size: size)
        case .spiderMan:        drawSpiderMan(ctx, size: size)
        case .captainAmerica:   drawCaptainAmerica(ctx, size: size)
        case .thor:             drawThor(ctx, size: size)
        case .hulk:             drawHulk(ctx, size: size)
        case .blackWidow:       drawBlackWidow(ctx, size: size)
        case .blackPanther:     drawBlackPanther(ctx, size: size)
        case .wolverine:        drawWolverine(ctx, size: size)
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

    // MARK: - Iron Man

    private static func drawIronMan(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2
        let headR = s * 0.32
        let headY = s * 0.62
        let bodyW = s * 0.28, bodyH = s * 0.22
        let bodyY = s * 0.25

        let red = CGColor(red: 0.78, green: 0.12, blue: 0.12, alpha: 1)
        let gold = CGColor(red: 0.90, green: 0.75, blue: 0.20, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW, h: s * 0.04)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: red, size: s)

        // Body — red armor
        let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH)
        outlinedEllipse(ctx, rect: bodyRect, fill: red, outline: ol)

        // Arc reactor — glowing blue circle on chest
        let arcR = s * 0.04
        let arcY = bodyY + bodyH * 0.1
        ctx.setFillColor(CGColor(red: 0.4, green: 0.7, blue: 1.0, alpha: 0.3))
        ctx.fillEllipse(in: CGRect(x: cx - arcR * 1.5, y: arcY - arcR * 1.5, width: arcR * 3, height: arcR * 3))
        outlinedEllipse(ctx, rect: CGRect(x: cx - arcR, y: arcY - arcR, width: arcR * 2, height: arcR * 2),
                        fill: CGColor(red: 0.6, green: 0.85, blue: 1.0, alpha: 1), outline: ol * 0.5)
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.8))
        ctx.fillEllipse(in: CGRect(x: cx - arcR * 0.4, y: arcY - arcR * 0.4, width: arcR * 0.8, height: arcR * 0.8))

        // Gold belt line
        outlinedRect(ctx, rect: CGRect(x: cx - bodyW * 0.4, y: bodyY - bodyH * 0.15, width: bodyW * 0.8, height: bodyH * 0.12),
                     fill: gold, outline: ol * 0.5)

        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: gold, size: s)

        // Helmet — red
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: red, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // Gold faceplate
        let faceW = headR * 0.65, faceH = headR * 0.75
        let faceY = headY - headR * 0.15
        let faceRect = CGRect(x: cx - faceW, y: faceY - faceH, width: faceW * 2, height: faceH * 2)
        ctx.saveGState()
        ctx.addEllipse(in: headRect)
        ctx.clip()
        outlinedEllipse(ctx, rect: faceRect, fill: gold, outline: ol * 0.5)
        ctx.restoreGState()

        // Eye slits — glowing white/blue
        let eyeSlitY = headY - headR * 0.05
        for dir: CGFloat in [-1, 1] {
            let ex = cx + dir * headR * 0.28
            ctx.saveGState()
            ctx.translateBy(x: ex, y: eyeSlitY)
            ctx.rotate(by: dir * 0.15)
            let slitW = headR * 0.22, slitH = headR * 0.10
            // Glow
            ctx.setFillColor(CGColor(red: 0.7, green: 0.9, blue: 1.0, alpha: 0.4))
            ctx.fillEllipse(in: CGRect(x: -slitW * 1.3, y: -slitH * 1.3, width: slitW * 2.6, height: slitH * 2.6))
            // Slit
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: -slitW, y: -slitH, width: slitW * 2, height: slitH * 2))
            ctx.restoreGState()
        }

        // Mouth slit
        ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 0.6))
        ctx.setLineWidth(s * 0.01)
        let mouthSlitY = headY - headR * 0.4
        ctx.move(to: CGPoint(x: cx - headR * 0.2, y: mouthSlitY))
        ctx.addLine(to: CGPoint(x: cx + headR * 0.2, y: mouthSlitY))
        ctx.strokePath()
    }

    // MARK: - Spider-Man

    private static func drawSpiderMan(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2
        let headR = s * 0.32
        let headY = s * 0.62
        let bodyW = s * 0.26, bodyH = s * 0.22
        let bodyY = s * 0.25

        let red = CGColor(red: 0.85, green: 0.10, blue: 0.10, alpha: 1)
        let blue = CGColor(red: 0.15, green: 0.25, blue: 0.70, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW, h: s * 0.04)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: red, size: s)

        // Body — blue suit
        let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH)
        outlinedEllipse(ctx, rect: bodyRect, fill: blue, outline: ol)

        // Red chest/shoulders area
        let chestRect = CGRect(x: cx - bodyW * 0.35, y: bodyY, width: bodyW * 0.7, height: bodyH * 0.5)
        ctx.saveGState()
        ctx.addEllipse(in: bodyRect)
        ctx.clip()
        ctx.setFillColor(red)
        ctx.fill(chestRect)
        ctx.restoreGState()

        // Spider emblem on chest — small black spider shape
        let spiderY = bodyY + bodyH * 0.12
        ctx.setFillColor(CGColor(gray: 0.05, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: cx - s * 0.015, y: spiderY - s * 0.012, width: s * 0.03, height: s * 0.024))
        // Spider legs (simplified)
        ctx.setStrokeColor(CGColor(gray: 0.05, alpha: 1))
        ctx.setLineWidth(s * 0.006)
        for dir: CGFloat in [-1, 1] {
            for j in 0..<3 {
                let angle = dir * (0.3 + CGFloat(j) * 0.35)
                let legLen = s * 0.03
                ctx.move(to: CGPoint(x: cx, y: spiderY))
                ctx.addLine(to: CGPoint(x: cx + cos(angle) * legLen * dir, y: spiderY + sin(angle) * legLen * 0.6))
            }
        }
        ctx.strokePath()

        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: red, size: s)

        // Head — red mask
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: red, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // Web lines on head
        ctx.setStrokeColor(CGColor(gray: 0.05, alpha: 0.4))
        ctx.setLineWidth(s * 0.006)
        // Radial lines from top of head
        for i in 0..<8 {
            let angle = CGFloat(i) * .pi / 8 + .pi * 0.06
            ctx.move(to: CGPoint(x: cx, y: headY + headR * 0.5))
            ctx.addLine(to: CGPoint(x: cx + cos(angle - .pi / 2) * headR * 0.9,
                                    y: headY + headR * 0.5 - sin(angle) * headR * 0.9))
        }
        ctx.strokePath()

        // Large white eye patches — lens-shaped
        let eyeY = headY - headR * 0.02
        for dir: CGFloat in [-1, 1] {
            let ex = cx + dir * headR * 0.32
            let ew = headR * 0.30, eh = headR * 0.25
            // Black outline
            ctx.setFillColor(CGColor(gray: 0.05, alpha: 1))
            ctx.saveGState()
            ctx.translateBy(x: ex, y: eyeY)
            ctx.rotate(by: dir * 0.1)
            ctx.fillEllipse(in: CGRect(x: -ew - 2, y: -eh - 2, width: (ew + 2) * 2, height: (eh + 2) * 2))
            // White lens
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: -ew, y: -eh, width: ew * 2, height: eh * 2))
            ctx.restoreGState()
        }
    }

    // MARK: - Captain America

    private static func drawCaptainAmerica(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2
        let headR = s * 0.32
        let headY = s * 0.62
        let bodyW = s * 0.28, bodyH = s * 0.22
        let bodyY = s * 0.25

        let blue = CGColor(red: 0.15, green: 0.30, blue: 0.70, alpha: 1)
        let red = CGColor(red: 0.80, green: 0.15, blue: 0.12, alpha: 1)
        let white = CGColor(gray: 0.95, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW, h: s * 0.04)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: red, size: s)

        // Shield behind body — visible circle
        let shieldR = s * 0.12
        let shieldX = cx + bodyW * 0.35
        let shieldY = bodyY + bodyH * 0.15
        outlinedEllipse(ctx, rect: CGRect(x: shieldX - shieldR, y: shieldY - shieldR, width: shieldR * 2, height: shieldR * 2),
                        fill: red, outline: ol)
        outlinedEllipse(ctx, rect: CGRect(x: shieldX - shieldR * 0.7, y: shieldY - shieldR * 0.7, width: shieldR * 1.4, height: shieldR * 1.4),
                        fill: white, outline: 0)
        outlinedEllipse(ctx, rect: CGRect(x: shieldX - shieldR * 0.45, y: shieldY - shieldR * 0.45, width: shieldR * 0.9, height: shieldR * 0.9),
                        fill: blue, outline: 0)
        // Star in center of shield
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        let starR = shieldR * 0.25
        drawStar(ctx, cx: shieldX, cy: shieldY, radius: starR, points: 5)

        // Body — blue with star
        let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH)
        outlinedEllipse(ctx, rect: bodyRect, fill: blue, outline: ol)

        // Red and white stripes on midsection
        ctx.saveGState()
        ctx.addEllipse(in: bodyRect)
        ctx.clip()
        let stripeH = bodyH * 0.08
        for i in 0..<4 {
            let sy = bodyY - bodyH * 0.25 + CGFloat(i) * stripeH * 2
            let stripeColor = (i % 2 == 0) ? red : white
            ctx.setFillColor(stripeColor)
            ctx.fill(CGRect(x: cx - bodyW / 2, y: sy, width: bodyW, height: stripeH))
        }
        ctx.restoreGState()

        // White star on chest
        let chestStarR = s * 0.035
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        drawStar(ctx, cx: cx, cy: bodyY + bodyH * 0.15, radius: chestStarR, points: 5)

        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: blue, size: s)

        // Helmet — blue
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: blue, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // White "A" on forehead
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        let aY = headY + headR * 0.35
        let aW = headR * 0.18
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
        ctx.setLineWidth(s * 0.02)
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: cx - aW, y: aY - headR * 0.25))
        ctx.addLine(to: CGPoint(x: cx, y: aY + headR * 0.1))
        ctx.addLine(to: CGPoint(x: cx + aW, y: aY - headR * 0.25))
        ctx.strokePath()
        // Crossbar of A
        ctx.setLineWidth(s * 0.012)
        ctx.move(to: CGPoint(x: cx - aW * 0.6, y: aY - headR * 0.08))
        ctx.addLine(to: CGPoint(x: cx + aW * 0.6, y: aY - headR * 0.08))
        ctx.strokePath()
        ctx.setLineCap(.butt)

        // Wings on sides of helmet
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        for dir: CGFloat in [-1, 1] {
            let wingX = cx + dir * headR * 0.7
            let wingY = headY + headR * 0.1
            ctx.move(to: CGPoint(x: wingX, y: wingY))
            ctx.addLine(to: CGPoint(x: wingX + dir * headR * 0.25, y: wingY + headR * 0.2))
            ctx.addLine(to: CGPoint(x: wingX + dir * headR * 0.15, y: wingY - headR * 0.05))
            ctx.fillPath()
        }

        // Face area — exposed lower face
        let faceColor = CGColor(red: 0.92, green: 0.78, blue: 0.65, alpha: 1)
        let faceRect = CGRect(x: cx - headR * 0.55, y: headY - headR * 0.7, width: headR * 1.1, height: headR * 0.8)
        ctx.saveGState()
        ctx.addEllipse(in: headRect)
        ctx.clip()
        outlinedEllipse(ctx, rect: faceRect, fill: faceColor, outline: ol * 0.5)
        ctx.restoreGState()

        drawSimpleEyes(ctx, cx: cx, headY: headY, headR: headR, size: s, spacing: 0.35)
        drawSmile(ctx, cx: cx, headY: headY, headR: headR, size: s)
    }

    // MARK: - Thor

    private static func drawThor(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2
        let headR = s * 0.32
        let headY = s * 0.62
        let bodyW = s * 0.28, bodyH = s * 0.22
        let bodyY = s * 0.25

        let silver = CGColor(gray: 0.75, alpha: 1)
        let blueTunic = CGColor(red: 0.20, green: 0.30, blue: 0.55, alpha: 1)
        let redCape = CGColor(red: 0.75, green: 0.12, blue: 0.12, alpha: 1)
        let skin = CGColor(red: 0.92, green: 0.78, blue: 0.65, alpha: 1)
        let blond = CGColor(red: 0.90, green: 0.80, blue: 0.40, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW * 1.1, h: s * 0.04)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: blueTunic, size: s)

        // Red cape behind body
        ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
        ctx.move(to: CGPoint(x: cx - bodyW * 0.7 - ol, y: bodyY - bodyH / 2 - s * 0.02))
        ctx.addLine(to: CGPoint(x: cx + bodyW * 0.7 + ol, y: bodyY - bodyH / 2 - s * 0.02))
        ctx.addLine(to: CGPoint(x: cx + bodyW * 0.5 + ol, y: bodyY + bodyH * 0.5 + ol))
        ctx.addLine(to: CGPoint(x: cx - bodyW * 0.5 - ol, y: bodyY + bodyH * 0.5 + ol))
        ctx.fillPath()
        ctx.setFillColor(redCape)
        ctx.move(to: CGPoint(x: cx - bodyW * 0.7, y: bodyY - bodyH / 2 - s * 0.02))
        ctx.addLine(to: CGPoint(x: cx + bodyW * 0.7, y: bodyY - bodyH / 2 - s * 0.02))
        ctx.addLine(to: CGPoint(x: cx + bodyW * 0.5, y: bodyY + bodyH * 0.5))
        ctx.addLine(to: CGPoint(x: cx - bodyW * 0.5, y: bodyY + bodyH * 0.5))
        ctx.fillPath()

        // Body — silver chest plate over blue tunic
        let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH)
        outlinedEllipse(ctx, rect: bodyRect, fill: blueTunic, outline: ol)

        // Silver chest armor
        let chestRect = CGRect(x: cx - bodyW * 0.3, y: bodyY + bodyH * 0.05, width: bodyW * 0.6, height: bodyH * 0.4)
        ctx.saveGState()
        ctx.addEllipse(in: bodyRect)
        ctx.clip()
        ctx.setFillColor(silver)
        ctx.fill(chestRect)
        ctx.restoreGState()

        // Silver circles on chest (discs)
        for dir: CGFloat in [-1, 1] {
            let discR = s * 0.015
            let discX = cx + dir * bodyW * 0.15
            let discY = bodyY + bodyH * 0.2
            ctx.setFillColor(CGColor(gray: 0.85, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: discX - discR, y: discY - discR, width: discR * 2, height: discR * 2))
        }

        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: skin, size: s)

        // Mjolnir — small hammer at side
        let hammerX = cx - bodyW / 2 - s * 0.06
        let hammerY = bodyY - bodyH * 0.1
        // Handle
        outlinedRect(ctx, rect: CGRect(x: hammerX - s * 0.008, y: hammerY - s * 0.05, width: s * 0.016, height: s * 0.07),
                     fill: CGColor(red: 0.50, green: 0.35, blue: 0.20, alpha: 1), outline: ol * 0.5)
        // Head
        outlinedRect(ctx, rect: CGRect(x: hammerX - s * 0.025, y: hammerY + s * 0.02, width: s * 0.05, height: s * 0.03),
                     fill: silver, outline: ol * 0.5)

        // Long blond hair behind head
        let hairRect = CGRect(x: cx - headR * 1.1, y: headY - headR * 0.6, width: headR * 2.2, height: headR * 1.8)
        outlinedEllipse(ctx, rect: hairRect, fill: blond, outline: ol)

        // Head
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: skin, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // Hair on top
        ctx.saveGState()
        ctx.addEllipse(in: headRect)
        ctx.clip()
        ctx.setFillColor(blond)
        ctx.fill(CGRect(x: cx - headR, y: headY + headR * 0.2, width: headR * 2, height: headR * 0.8))
        ctx.restoreGState()

        // Silver winged helmet
        ctx.setFillColor(silver)
        ctx.fill(CGRect(x: cx - headR * 0.4, y: headY + headR * 0.55, width: headR * 0.8, height: headR * 0.3))
        // Wings on helmet
        for dir: CGFloat in [-1, 1] {
            let wingX = cx + dir * headR * 0.5
            let wingY = headY + headR * 0.65
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.move(to: CGPoint(x: wingX, y: wingY))
            ctx.addLine(to: CGPoint(x: wingX + dir * headR * 0.3, y: wingY + headR * 0.25))
            ctx.addLine(to: CGPoint(x: wingX + dir * headR * 0.1, y: wingY - headR * 0.05))
            ctx.fillPath()
        }

        drawSimpleEyes(ctx, cx: cx, headY: headY, headR: headR, size: s, spacing: 0.38)
        drawSmile(ctx, cx: cx, headY: headY, headR: headR, size: s)
    }

    // MARK: - Hulk

    private static func drawHulk(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2
        let headR = s * 0.34
        let headY = s * 0.60
        let bodyW = s * 0.36, bodyH = s * 0.24  // wider body
        let bodyY = s * 0.25

        let green = CGColor(red: 0.25, green: 0.62, blue: 0.18, alpha: 1)
        let darkGreen = CGColor(red: 0.18, green: 0.45, blue: 0.12, alpha: 1)
        let purple = CGColor(red: 0.45, green: 0.15, blue: 0.55, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW * 1.2, h: s * 0.05)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: green, size: s)

        // Torn purple shorts
        let shortsRect = CGRect(x: cx - bodyW * 0.45, y: bodyY - bodyH * 0.45, width: bodyW * 0.9, height: bodyH * 0.5)
        outlinedRect(ctx, rect: shortsRect, fill: purple, outline: ol)
        // Torn edges — jagged bottom
        ctx.setFillColor(purple)
        for i in 0..<5 {
            let tx = cx - bodyW * 0.35 + CGFloat(i) * bodyW * 0.17
            let ty = bodyY - bodyH * 0.45 - s * 0.015
            ctx.move(to: CGPoint(x: tx, y: shortsRect.minY))
            ctx.addLine(to: CGPoint(x: tx + bodyW * 0.08, y: ty))
            ctx.addLine(to: CGPoint(x: tx + bodyW * 0.16, y: shortsRect.minY))
            ctx.fillPath()
        }

        // Body — wide green torso, no shirt
        let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH)
        outlinedEllipse(ctx, rect: bodyRect, fill: green, outline: ol)

        // Chest definition lines
        ctx.setStrokeColor(darkGreen)
        ctx.setLineWidth(s * 0.008)
        ctx.move(to: CGPoint(x: cx, y: bodyY + bodyH * 0.35))
        ctx.addLine(to: CGPoint(x: cx, y: bodyY))
        ctx.strokePath()

        // Massive arms — wider than normal
        for dir: CGFloat in [-1, 1] {
            let ax = cx + dir * (bodyW / 2 + s * 0.05)
            let ay = bodyY + bodyH * 0.05
            ctx.saveGState()
            ctx.translateBy(x: ax, y: ay)
            ctx.rotate(by: dir * 0.25)
            let armRect = CGRect(x: -s * 0.045, y: -s * 0.07, width: s * 0.09, height: s * 0.14)
            outlinedEllipse(ctx, rect: armRect, fill: green, outline: ol)
            ctx.restoreGState()
        }

        // Head — green
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: green, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // Dark green messy hair
        ctx.setFillColor(darkGreen)
        ctx.saveGState()
        ctx.addEllipse(in: headRect)
        ctx.clip()
        // Jagged hair on top
        for i in 0..<6 {
            let hx = cx - headR * 0.6 + CGFloat(i) * headR * 0.25
            let hy = headY + headR * 0.6
            ctx.move(to: CGPoint(x: hx, y: headY + headR * 0.3))
            ctx.addLine(to: CGPoint(x: hx + headR * 0.12, y: hy + headR * CGFloat(i % 2) * 0.15))
            ctx.addLine(to: CGPoint(x: hx + headR * 0.24, y: headY + headR * 0.3))
            ctx.fillPath()
        }
        ctx.restoreGState()

        // Angry brow — heavy brow ridge
        ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
        ctx.setLineWidth(s * 0.025)
        ctx.setLineCap(.round)
        for dir: CGFloat in [-1, 1] {
            let browX = cx + dir * headR * 0.15
            let browEndX = cx + dir * headR * 0.5
            ctx.move(to: CGPoint(x: browX, y: headY + headR * 0.15))
            ctx.addLine(to: CGPoint(x: browEndX, y: headY + headR * 0.05))
        }
        ctx.strokePath()
        ctx.setLineCap(.butt)

        // Squinting angry eyes — smaller
        let eyeY = headY - headR * 0.05
        let sp = headR * 0.35
        for dir: CGFloat in [-1, 1] {
            let ex = cx + dir * sp
            let ew = headR * 0.20, eh = headR * 0.14
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex - ew - 1.5, y: eyeY - eh - 1.5, width: (ew + 1.5) * 2, height: (eh + 1.5) * 2))
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex - ew, y: eyeY - eh, width: ew * 2, height: eh * 2))
            let pw = ew * 0.6, ph = eh * 0.6
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex - pw, y: eyeY - ph, width: pw * 2, height: ph * 2))
        }

        // Angry scowl mouth
        ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
        ctx.setLineWidth(max(s * 0.02, 1.5))
        ctx.setLineCap(.round)
        let mouthY = headY - headR * 0.4
        ctx.addArc(center: CGPoint(x: cx, y: mouthY - headR * 0.05),
                   radius: headR * 0.15,
                   startAngle: .pi * 0.15,
                   endAngle: .pi * 0.85,
                   clockwise: false)
        ctx.strokePath()
        ctx.setLineCap(.butt)
    }

    // MARK: - Black Widow

    private static func drawBlackWidow(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2
        let headR = s * 0.30
        let headY = s * 0.62
        let bodyW = s * 0.26, bodyH = s * 0.22
        let bodyY = s * 0.25

        let black = CGColor(gray: 0.12, alpha: 1)
        let skin = CGColor(red: 0.92, green: 0.78, blue: 0.65, alpha: 1)
        let redHair = CGColor(red: 0.72, green: 0.18, blue: 0.10, alpha: 1)
        let silverGauntlet = CGColor(gray: 0.70, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW, h: s * 0.04)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: black, size: s)

        // Body — black bodysuit
        let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH)
        outlinedEllipse(ctx, rect: bodyRect, fill: black, outline: ol)

        // Belt with red hourglass
        let beltH = bodyH * 0.12
        let beltY = bodyY - bodyH * 0.05
        outlinedRect(ctx, rect: CGRect(x: cx - bodyW * 0.4, y: beltY - beltH / 2, width: bodyW * 0.8, height: beltH),
                     fill: CGColor(gray: 0.2, alpha: 1), outline: ol * 0.5)
        // Red hourglass symbol
        ctx.setFillColor(CGColor(red: 0.85, green: 0.10, blue: 0.10, alpha: 1))
        let hgW = s * 0.015, hgH = s * 0.018
        ctx.move(to: CGPoint(x: cx - hgW, y: beltY + hgH))
        ctx.addLine(to: CGPoint(x: cx + hgW, y: beltY + hgH))
        ctx.addLine(to: CGPoint(x: cx, y: beltY))
        ctx.fillPath()
        ctx.move(to: CGPoint(x: cx - hgW, y: beltY - hgH))
        ctx.addLine(to: CGPoint(x: cx + hgW, y: beltY - hgH))
        ctx.addLine(to: CGPoint(x: cx, y: beltY))
        ctx.fillPath()

        // Arms with silver wrist gauntlets
        for dir: CGFloat in [-1, 1] {
            let ax = cx + dir * (bodyW / 2 + s * 0.04)
            let ay = bodyY + bodyH * 0.05
            ctx.saveGState()
            ctx.translateBy(x: ax, y: ay)
            ctx.rotate(by: dir * 0.3)
            let armRect = CGRect(x: -s * 0.03, y: -s * 0.055, width: s * 0.06, height: s * 0.11)
            outlinedEllipse(ctx, rect: armRect, fill: black, outline: ol)
            // Gauntlet band
            let gauntletRect = CGRect(x: -s * 0.032, y: -s * 0.055, width: s * 0.064, height: s * 0.025)
            outlinedRect(ctx, rect: gauntletRect, fill: silverGauntlet, outline: ol * 0.3)
            ctx.restoreGState()
        }

        // Red hair behind head — shoulder length with wave
        let hairRect = CGRect(x: cx - headR * 1.2, y: headY - headR * 0.8, width: headR * 2.4, height: headR * 2.0)
        outlinedEllipse(ctx, rect: hairRect, fill: redHair, outline: ol)

        // Head
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: skin, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // Hair on top of head
        ctx.saveGState()
        ctx.addEllipse(in: headRect)
        ctx.clip()
        ctx.setFillColor(redHair)
        ctx.fill(CGRect(x: cx - headR, y: headY + headR * 0.3, width: headR * 2, height: headR * 0.7))
        ctx.restoreGState()

        drawSimpleEyes(ctx, cx: cx, headY: headY, headR: headR, size: s, spacing: 0.35)

        // Determined expression — straight mouth
        ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
        ctx.setLineWidth(max(s * 0.016, 1.2))
        ctx.setLineCap(.round)
        let mouthY = headY - headR * 0.38
        ctx.move(to: CGPoint(x: cx - headR * 0.12, y: mouthY))
        ctx.addLine(to: CGPoint(x: cx + headR * 0.12, y: mouthY))
        ctx.strokePath()
        ctx.setLineCap(.butt)
    }

    // MARK: - Black Panther

    private static func drawBlackPanther(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2
        let headR = s * 0.32
        let headY = s * 0.62
        let bodyW = s * 0.28, bodyH = s * 0.22
        let bodyY = s * 0.25

        let black = CGColor(gray: 0.10, alpha: 1)
        let darkGray = CGColor(gray: 0.18, alpha: 1)
        let purple = CGColor(red: 0.50, green: 0.30, blue: 0.75, alpha: 1)
        let silver = CGColor(gray: 0.75, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW, h: s * 0.04)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: black, size: s)

        // Body — black suit
        let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH)
        outlinedEllipse(ctx, rect: bodyRect, fill: darkGray, outline: ol)

        // Purple energy lines on suit
        ctx.setStrokeColor(purple)
        ctx.setLineWidth(s * 0.008)
        ctx.setLineCap(.round)
        // V-shape lines on chest
        ctx.move(to: CGPoint(x: cx - bodyW * 0.3, y: bodyY + bodyH * 0.3))
        ctx.addLine(to: CGPoint(x: cx, y: bodyY))
        ctx.addLine(to: CGPoint(x: cx + bodyW * 0.3, y: bodyY + bodyH * 0.3))
        ctx.strokePath()
        // Horizontal line
        ctx.move(to: CGPoint(x: cx - bodyW * 0.25, y: bodyY - bodyH * 0.1))
        ctx.addLine(to: CGPoint(x: cx + bodyW * 0.25, y: bodyY - bodyH * 0.1))
        ctx.strokePath()
        ctx.setLineCap(.butt)

        // Vibranium necklace
        let neckR = bodyW * 0.22
        let neckY = bodyY + bodyH * 0.4
        ctx.setStrokeColor(silver)
        ctx.setLineWidth(s * 0.012)
        ctx.addArc(center: CGPoint(x: cx, y: neckY),
                   radius: neckR,
                   startAngle: .pi * 0.2,
                   endAngle: .pi * 0.8,
                   clockwise: false)
        ctx.strokePath()
        // Fangs/teeth detail on necklace
        for i in 0..<5 {
            let angle = .pi * 0.25 + CGFloat(i) * .pi * 0.125
            let tx = cx + cos(angle) * neckR
            let ty = neckY + sin(angle) * neckR
            ctx.setFillColor(silver)
            ctx.fillEllipse(in: CGRect(x: tx - s * 0.008, y: ty - s * 0.008, width: s * 0.016, height: s * 0.016))
        }

        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: darkGray, size: s)

        // Head — black mask covering entire head
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: black, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // Cat ear points on mask
        for dir: CGFloat in [-1, 1] {
            let earX = cx + dir * headR * 0.45
            let earBaseY = headY + headR * 0.65
            let earTipY = headY + headR * 1.05
            // Outline
            ctx.setFillColor(CGColor(gray: 0.05, alpha: 1))
            ctx.move(to: CGPoint(x: earX - headR * 0.15, y: earBaseY))
            ctx.addLine(to: CGPoint(x: earX, y: earTipY + ol))
            ctx.addLine(to: CGPoint(x: earX + headR * 0.15, y: earBaseY))
            ctx.fillPath()
            // Fill
            ctx.setFillColor(black)
            ctx.move(to: CGPoint(x: earX - headR * 0.12, y: earBaseY))
            ctx.addLine(to: CGPoint(x: earX, y: earTipY))
            ctx.addLine(to: CGPoint(x: earX + headR * 0.12, y: earBaseY))
            ctx.fillPath()
        }

        // White eye slits
        let eyeSlitY = headY - headR * 0.02
        for dir: CGFloat in [-1, 1] {
            let ex = cx + dir * headR * 0.3
            ctx.saveGState()
            ctx.translateBy(x: ex, y: eyeSlitY)
            ctx.rotate(by: dir * 0.15)
            let slitW = headR * 0.22, slitH = headR * 0.08
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: -slitW, y: -slitH, width: slitW * 2, height: slitH * 2))
            ctx.restoreGState()
        }

        // Purple energy highlight on mask
        ctx.setStrokeColor(CGColor(red: 0.55, green: 0.35, blue: 0.80, alpha: 0.4))
        ctx.setLineWidth(s * 0.006)
        ctx.addArc(center: CGPoint(x: cx, y: headY), radius: headR * 0.7,
                   startAngle: .pi * 0.3, endAngle: .pi * 0.7, clockwise: false)
        ctx.strokePath()
    }

    // MARK: - Wolverine

    private static func drawWolverine(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2
        let headR = s * 0.32
        let headY = s * 0.62
        let bodyW = s * 0.28, bodyH = s * 0.22
        let bodyY = s * 0.25

        let yellow = CGColor(red: 0.92, green: 0.82, blue: 0.15, alpha: 1)
        let blueSuit = CGColor(red: 0.15, green: 0.25, blue: 0.60, alpha: 1)
        let skin = CGColor(red: 0.90, green: 0.75, blue: 0.60, alpha: 1)
        let clawSilver = CGColor(gray: 0.85, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW, h: s * 0.04)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: yellow, size: s)

        // Body — yellow/blue suit
        let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH)
        outlinedEllipse(ctx, rect: bodyRect, fill: yellow, outline: ol)

        // Blue sides of suit
        ctx.saveGState()
        ctx.addEllipse(in: bodyRect)
        ctx.clip()
        ctx.setFillColor(blueSuit)
        ctx.fill(CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW * 0.2, height: bodyH))
        ctx.fill(CGRect(x: cx + bodyW * 0.3, y: bodyY - bodyH / 2, width: bodyW * 0.2, height: bodyH))
        ctx.restoreGState()

        // Belt
        outlinedRect(ctx, rect: CGRect(x: cx - bodyW * 0.4, y: bodyY - bodyH * 0.1, width: bodyW * 0.8, height: bodyH * 0.1),
                     fill: blueSuit, outline: ol * 0.5)
        // Belt buckle
        let buckleR = s * 0.015
        outlinedEllipse(ctx, rect: CGRect(x: cx - buckleR, y: bodyY - bodyH * 0.05 - buckleR, width: buckleR * 2, height: buckleR * 2),
                        fill: yellow, outline: ol * 0.3)

        // Arms with claws
        for dir: CGFloat in [-1, 1] {
            let ax = cx + dir * (bodyW / 2 + s * 0.04)
            let ay = bodyY + bodyH * 0.05
            ctx.saveGState()
            ctx.translateBy(x: ax, y: ay)
            ctx.rotate(by: dir * 0.3)
            let armRect = CGRect(x: -s * 0.03, y: -s * 0.055, width: s * 0.06, height: s * 0.11)
            outlinedEllipse(ctx, rect: armRect, fill: blueSuit, outline: ol)

            // 3 metal claws extending from fist
            ctx.setStrokeColor(clawSilver)
            ctx.setLineWidth(s * 0.012)
            ctx.setLineCap(.round)
            for j in -1...1 {
                let clawStartY = -s * 0.055
                let clawEndY = clawStartY - s * 0.06
                let clawX = CGFloat(j) * s * 0.012
                ctx.move(to: CGPoint(x: clawX, y: clawStartY))
                ctx.addLine(to: CGPoint(x: clawX, y: clawEndY))
            }
            ctx.strokePath()
            ctx.setLineCap(.butt)
            ctx.restoreGState()
        }

        // Head — yellow mask with tall ear points
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: yellow, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // Tall ear-points on mask
        for dir: CGFloat in [-1, 1] {
            let earX = cx + dir * headR * 0.5
            let earBaseY = headY + headR * 0.6
            let earTipY = headY + headR * 1.25
            // Outline
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.move(to: CGPoint(x: earX - headR * 0.18, y: earBaseY))
            ctx.addLine(to: CGPoint(x: earX, y: earTipY + ol * 2))
            ctx.addLine(to: CGPoint(x: earX + headR * 0.18, y: earBaseY))
            ctx.fillPath()
            // Fill
            ctx.setFillColor(yellow)
            ctx.move(to: CGPoint(x: earX - headR * 0.15, y: earBaseY))
            ctx.addLine(to: CGPoint(x: earX, y: earTipY))
            ctx.addLine(to: CGPoint(x: earX + headR * 0.15, y: earBaseY))
            ctx.fillPath()
        }

        // Black face visible through mask opening
        let faceRect = CGRect(x: cx - headR * 0.55, y: headY - headR * 0.65, width: headR * 1.1, height: headR * 0.85)
        ctx.saveGState()
        ctx.addEllipse(in: headRect)
        ctx.clip()
        outlinedEllipse(ctx, rect: faceRect, fill: skin, outline: ol * 0.5)
        ctx.restoreGState()

        // Mutton chop sideburns
        ctx.setFillColor(CGColor(gray: 0.15, alpha: 1))
        for dir: CGFloat in [-1, 1] {
            let sideX = cx + dir * headR * 0.4
            let sideY = headY - headR * 0.2
            ctx.fill(CGRect(x: sideX - s * 0.015, y: sideY - s * 0.04, width: s * 0.03, height: s * 0.06))
        }

        // Angry eyes — small and fierce
        let eyeY = headY - headR * 0.05
        let sp = headR * 0.32
        for dir: CGFloat in [-1, 1] {
            let ex = cx + dir * sp
            let ew = headR * 0.20, eh = headR * 0.16
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex - ew - 1.5, y: eyeY - eh - 1.5, width: (ew + 1.5) * 2, height: (eh + 1.5) * 2))
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex - ew, y: eyeY - eh, width: ew * 2, height: eh * 2))
            let pw = ew * 0.55, ph = eh * 0.55
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex - pw, y: eyeY - ph, width: pw * 2, height: ph * 2))
        }

        // Angry brow
        ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
        ctx.setLineWidth(s * 0.02)
        ctx.setLineCap(.round)
        for dir: CGFloat in [-1, 1] {
            ctx.move(to: CGPoint(x: cx + dir * headR * 0.12, y: headY + headR * 0.15))
            ctx.addLine(to: CGPoint(x: cx + dir * headR * 0.45, y: headY + headR * 0.0))
        }
        ctx.strokePath()
        ctx.setLineCap(.butt)

        // Angry scowl
        ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
        ctx.setLineWidth(max(s * 0.018, 1.2))
        ctx.setLineCap(.round)
        let mouthY = headY - headR * 0.38
        ctx.addArc(center: CGPoint(x: cx, y: mouthY - headR * 0.05),
                   radius: headR * 0.12,
                   startAngle: .pi * 0.15,
                   endAngle: .pi * 0.85,
                   clockwise: false)
        ctx.strokePath()
        ctx.setLineCap(.butt)
    }

    // MARK: - Star Drawing Helper

    private static func drawStar(_ ctx: CGContext, cx: CGFloat, cy: CGFloat, radius: CGFloat, points: Int) {
        let innerRadius = radius * 0.4
        let path = CGMutablePath()
        for i in 0..<(points * 2) {
            let angle = CGFloat(i) * .pi / CGFloat(points) + .pi / 2
            let r = (i % 2 == 0) ? radius : innerRadius
            let px = cx + cos(angle) * r
            let py = cy + sin(angle) * r
            if i == 0 {
                path.move(to: CGPoint(x: px, y: py))
            } else {
                path.addLine(to: CGPoint(x: px, y: py))
            }
        }
        path.closeSubpath()
        ctx.addPath(path)
        ctx.fillPath()
    }
}
