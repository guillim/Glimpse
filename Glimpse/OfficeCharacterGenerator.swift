// Glimpse/OfficeCharacterGenerator.swift
import AppKit

/// Generates chibi The Office characters procedurally using Core Graphics.
/// Same architecture as StarWarsCharacterGenerator — deterministic mapping from sessionID.
enum OfficeCharacterGenerator {

    // MARK: - Character Definitions

    enum Character: Int, CaseIterable {
        case dwight = 0
        case michael
        case jim
        case pam
        case angela
        case kevin
        case stanley
        case creed
    }

    /// Representative color for each character (used for menu bar dot).
    static func color(for sessionID: String) -> NSColor {
        let ch = character(for: sessionID)
        switch ch {
        case .michael:  return NSColor(red: 0.15, green: 0.20, blue: 0.35, alpha: 1)
        case .dwight:   return NSColor(red: 0.72, green: 0.58, blue: 0.20, alpha: 1)
        case .jim:      return NSColor(red: 0.45, green: 0.55, blue: 0.70, alpha: 1)
        case .pam:      return NSColor(red: 0.78, green: 0.55, blue: 0.55, alpha: 1)
        case .angela:   return NSColor(red: 0.85, green: 0.82, blue: 0.72, alpha: 1)
        case .kevin:    return NSColor(red: 0.40, green: 0.58, blue: 0.38, alpha: 1)
        case .stanley:  return NSColor(red: 0.55, green: 0.42, blue: 0.32, alpha: 1)
        case .creed:    return NSColor(red: 0.65, green: 0.65, blue: 0.65, alpha: 1)
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

    // MARK: - Seeded RNG

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
        if roll < 9 { return Character(rawValue: 0)! }
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
        case .michael:  drawMichael(ctx, size: size)
        case .dwight:   drawDwight(ctx, size: size)
        case .jim:      drawJim(ctx, size: size)
        case .pam:      drawPam(ctx, size: size)
        case .angela:   drawAngela(ctx, size: size)
        case .kevin:    drawKevin(ctx, size: size)
        case .stanley:  drawStanley(ctx, size: size)
        case .creed:    drawCreed(ctx, size: size)
        }

        guard let image = ctx.makeImage() else { return nil }
        cache.setObject(CGImageBox(image), forKey: cacheKey)
        return image
    }

    // MARK: - Drawing Helpers

    private static let ol: CGFloat = 1.5

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

    private static func headHighlight(_ ctx: CGContext, cx: CGFloat, headY: CGFloat, headR: CGFloat) {
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
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

    private static func drawShadow(_ ctx: CGContext, cx: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) {
        ctx.setFillColor(CGColor(gray: 0, alpha: 0.2))
        ctx.fillEllipse(in: CGRect(x: cx - w / 2, y: y, width: w, height: h))
    }

    private static func drawFeet(_ ctx: CGContext, cx: CGFloat, footY: CGFloat, bodyW: CGFloat, fill: CGColor, size s: CGFloat) {
        for dir: CGFloat in [-1, 1] {
            let fx = cx + dir * bodyW * 0.35
            outlinedEllipse(ctx, rect: CGRect(x: fx - s * 0.045, y: footY - s * 0.025, width: s * 0.09, height: s * 0.05), fill: fill, outline: ol)
        }
    }

    private static func drawArms(_ ctx: CGContext, cx: CGFloat, bodyY: CGFloat, bodyW: CGFloat, bodyH: CGFloat, fill: CGColor, size s: CGFloat) {
        for dir: CGFloat in [-1, 1] {
            let ax = cx + dir * (bodyW / 2 + s * 0.04)
            let ay = bodyY + bodyH * 0.05
            ctx.saveGState()
            ctx.translateBy(x: ax, y: ay)
            ctx.rotate(by: dir * 0.3)
            outlinedEllipse(ctx, rect: CGRect(x: -s * 0.03, y: -s * 0.055, width: s * 0.06, height: s * 0.11), fill: fill, outline: ol)
            ctx.restoreGState()
        }
    }

    /// Eyes with per-character customization.
    private static func drawEyes(
        _ ctx: CGContext, cx: CGFloat, eyeY: CGFloat,
        spacing: CGFloat, ew: CGFloat, eh: CGFloat,
        skin: CGColor, halfLid: CGFloat = 0,
        pupilScale: CGFloat = 0.55,
        pupilOffsets: [(CGFloat, CGFloat)]? = nil
    ) {
        for (i, dir): (Int, CGFloat) in [(0, -1.0 as CGFloat), (1, 1.0 as CGFloat)] {
            let ex = cx + dir * spacing
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex - ew - 1.5, y: eyeY - eh - 1.5, width: (ew + 1.5) * 2, height: (eh + 1.5) * 2))
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex - ew, y: eyeY - eh, width: ew * 2, height: eh * 2))
            let pox = pupilOffsets?[i].0 ?? 0
            let poy = pupilOffsets?[i].1 ?? 0
            let pw = ew * pupilScale, ph = eh * pupilScale
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex + pox - pw, y: eyeY + poy - ph, width: pw * 2, height: ph * 2))
            let hlR = ew * 0.28
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex + pox + ew * 0.18 - hlR / 2, y: eyeY + poy + eh * 0.22 - hlR / 2, width: hlR, height: hlR))
            if halfLid > 0 {
                ctx.setFillColor(skin)
                let lidH = eh * 2 * halfLid
                ctx.fillEllipse(in: CGRect(x: ex - ew * 1.15, y: eyeY + eh - lidH * 0.15, width: ew * 2.3, height: lidH))
            }
        }
    }

    /// Rectangular glasses (Dwight-style).
    private static func drawRectGlasses(_ ctx: CGContext, cx: CGFloat, gy: CGFloat, headR: CGFloat, s: CGFloat) {
        ctx.setStrokeColor(CGColor(gray: 0.15, alpha: 1))
        ctx.setLineWidth(s * 0.02)
        for dir: CGFloat in [-1, 1] {
            let gx = cx + dir * headR * 0.34
            let gw = headR * 0.28, gh = headR * 0.20
            ctx.stroke(CGRect(x: gx - gw, y: gy - gh, width: gw * 2, height: gh * 2))
        }
        ctx.move(to: CGPoint(x: cx - headR * 0.06, y: gy))
        ctx.addLine(to: CGPoint(x: cx + headR * 0.06, y: gy))
        ctx.strokePath()
    }

    /// Round glasses (Stanley-style).
    private static func drawRoundGlasses(_ ctx: CGContext, cx: CGFloat, gy: CGFloat, headR: CGFloat, s: CGFloat) {
        ctx.setStrokeColor(CGColor(gray: 0.15, alpha: 1))
        ctx.setLineWidth(s * 0.016)
        for dir: CGFloat in [-1, 1] {
            let gx = cx + dir * headR * 0.33
            let gr = headR * 0.22
            ctx.addEllipse(in: CGRect(x: gx - gr, y: gy - gr, width: gr * 2, height: gr * 2))
        }
        ctx.strokePath()
        ctx.move(to: CGPoint(x: cx - headR * 0.11, y: gy + headR * 0.02))
        ctx.addLine(to: CGPoint(x: cx + headR * 0.11, y: gy + headR * 0.02))
        ctx.strokePath()
    }

    /// Tie shape.
    private static func drawTie(_ ctx: CGContext, cx: CGFloat, bodyY: CGFloat, bodyH: CGFloat, color: CGColor, s: CGFloat) {
        let tieW = s * 0.024
        ctx.setFillColor(color)
        ctx.move(to: CGPoint(x: cx - tieW, y: bodyY + bodyH * 0.33))
        ctx.addLine(to: CGPoint(x: cx + tieW, y: bodyY + bodyH * 0.33))
        ctx.addLine(to: CGPoint(x: cx + tieW * 0.7, y: bodyY - bodyH * 0.08))
        ctx.addLine(to: CGPoint(x: cx, y: bodyY - bodyH * 0.18))
        ctx.addLine(to: CGPoint(x: cx - tieW * 0.7, y: bodyY - bodyH * 0.08))
        ctx.fillPath()
    }

    /// Shirt collar V.
    private static func drawCollar(_ ctx: CGContext, cx: CGFloat, bodyY: CGFloat, bodyW: CGFloat, bodyH: CGFloat, color: CGColor) {
        ctx.setFillColor(color)
        ctx.move(to: CGPoint(x: cx - bodyW * 0.16, y: bodyY + bodyH * 0.42))
        ctx.addLine(to: CGPoint(x: cx + bodyW * 0.16, y: bodyY + bodyH * 0.42))
        ctx.addLine(to: CGPoint(x: cx, y: bodyY + bodyH * 0.05))
        ctx.fillPath()
    }

    // =========================================================================
    // MARK: - Character Drawings
    // =========================================================================

    // MARK: - Michael Scott

    private static func drawMichael(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2, headR = s * 0.34, headY = s * 0.62
        let bodyW = s * 0.28, bodyH = s * 0.22, bodyY = s * 0.25
        let skin = CGColor(red: 0.93, green: 0.81, blue: 0.71, alpha: 1)
        let suit = CGColor(red: 0.10, green: 0.12, blue: 0.25, alpha: 1)
        let shirt = CGColor(red: 0.58, green: 0.68, blue: 0.85, alpha: 1)
        let hair = CGColor(red: 0.25, green: 0.18, blue: 0.10, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW, h: s * 0.04)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: CGColor(gray: 0.15, alpha: 1), size: s)
        outlinedEllipse(ctx, rect: CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH), fill: suit, outline: ol)
        drawCollar(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, color: shirt)
        drawTie(ctx, cx: cx, bodyY: bodyY, bodyH: bodyH, color: CGColor(red: 0.80, green: 0.18, blue: 0.18, alpha: 1), s: s)
        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: suit, size: s)

        // Head
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: skin, outline: ol)
        headHighlight(ctx, cx: cx, headY: headY, headR: headR)

        // Hair — short dark brown, combed right with volume on top
        ctx.saveGState()
        ctx.addEllipse(in: headRect); ctx.clip()
        ctx.setFillColor(hair)
        ctx.fill(CGRect(x: cx - headR, y: headY + headR * 0.20, width: headR * 2, height: headR * 0.85))
        // Side part
        ctx.setFillColor(CGColor(red: 0.18, green: 0.12, blue: 0.06, alpha: 0.5))
        ctx.fill(CGRect(x: cx - headR * 0.20, y: headY + headR * 0.45, width: headR * 0.04, height: headR * 0.40))
        ctx.restoreGState()
        // Volume bump at front
        ctx.setFillColor(hair)
        ctx.move(to: CGPoint(x: cx - headR * 0.50, y: headY + headR * 0.48))
        ctx.addQuadCurve(to: CGPoint(x: cx + headR * 0.60, y: headY + headR * 0.45),
                         control: CGPoint(x: cx + headR * 0.05, y: headY + headR * 0.95))
        ctx.addLine(to: CGPoint(x: cx + headR * 0.60, y: headY + headR * 0.35))
        ctx.addLine(to: CGPoint(x: cx - headR * 0.50, y: headY + headR * 0.38))
        ctx.fillPath()

        // Eyes — big and round (eager)
        let eyeY = headY - headR * 0.05
        drawEyes(ctx, cx: cx, eyeY: eyeY, spacing: headR * 0.36, ew: headR * 0.24, eh: headR * 0.30, skin: skin)

        // Eyebrows
        ctx.setStrokeColor(CGColor(red: 0.25, green: 0.16, blue: 0.08, alpha: 0.7))
        ctx.setLineWidth(s * 0.012); ctx.setLineCap(.round)
        for dir: CGFloat in [-1, 1] {
            let bx = cx + dir * headR * 0.36
            ctx.move(to: CGPoint(x: bx - headR * 0.12, y: eyeY + headR * 0.28))
            ctx.addLine(to: CGPoint(x: bx + headR * 0.12, y: eyeY + headR * 0.30))
        }
        ctx.strokePath(); ctx.setLineCap(.butt)

        // Wide toothy grin — open mouth with white teeth band
        let my = headY - headR * 0.45, mw = headR * 0.32, mh = headR * 0.14
        ctx.setFillColor(CGColor(red: 0.35, green: 0.10, blue: 0.08, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: cx - mw, y: my - mh, width: mw * 2, height: mh * 2))
        ctx.setFillColor(CGColor(gray: 0.96, alpha: 1))
        ctx.fill(CGRect(x: cx - mw * 0.80, y: my + mh * 0.05, width: mw * 1.60, height: mh * 0.70))
    }

    // MARK: - Dwight Schrute

    private static func drawDwight(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2, headR = s * 0.34, headY = s * 0.63
        let bodyW = s * 0.28, bodyH = s * 0.22, bodyY = s * 0.25
        let skin = CGColor(red: 0.92, green: 0.82, blue: 0.72, alpha: 1)
        let shirt = CGColor(red: 0.78, green: 0.68, blue: 0.22, alpha: 1)  // mustard
        let suitJacket = CGColor(red: 0.42, green: 0.32, blue: 0.18, alpha: 1)
        let hair = CGColor(red: 0.32, green: 0.22, blue: 0.12, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW, h: s * 0.04)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: CGColor(gray: 0.18, alpha: 1), size: s)
        outlinedEllipse(ctx, rect: CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH), fill: suitJacket, outline: ol)
        drawCollar(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, color: shirt)
        drawTie(ctx, cx: cx, bodyY: bodyY, bodyH: bodyH, color: CGColor(red: 0.58, green: 0.08, blue: 0.12, alpha: 1), s: s)
        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: suitJacket, size: s)

        // Head
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: skin, outline: ol)
        headHighlight(ctx, cx: cx, headY: headY, headR: headR)

        // Bowl cut — center part, hair hangs straight down on sides
        ctx.saveGState()
        ctx.addEllipse(in: headRect); ctx.clip()
        ctx.setFillColor(hair)
        ctx.fill(CGRect(x: cx - headR, y: headY + headR * 0.05, width: headR * 2, height: headR))
        // Center part
        ctx.setFillColor(skin)
        ctx.move(to: CGPoint(x: cx - headR * 0.04, y: headY + headR * 1.02))
        ctx.addLine(to: CGPoint(x: cx + headR * 0.04, y: headY + headR * 1.02))
        ctx.addLine(to: CGPoint(x: cx + headR * 0.12, y: headY + headR * 0.45))
        ctx.addLine(to: CGPoint(x: cx - headR * 0.12, y: headY + headR * 0.45))
        ctx.fillPath()
        // Bowl fringe cutout
        ctx.fillEllipse(in: CGRect(x: cx - headR * 1.2, y: headY - headR * 0.30, width: headR * 2.4, height: headR * 0.60))
        ctx.restoreGState()

        // Rectangular glasses
        let gy = headY + headR * 0.02
        drawRectGlasses(ctx, cx: cx, gy: gy, headR: headR, s: s)

        // Squinting eyes behind glasses
        let eyeY = headY - headR * 0.02
        drawEyes(ctx, cx: cx, eyeY: eyeY, spacing: headR * 0.34, ew: headR * 0.20, eh: headR * 0.22, skin: skin, halfLid: 0.35, pupilScale: 0.50)

        // Angry eyebrows — angled inward
        ctx.setStrokeColor(CGColor(red: 0.28, green: 0.18, blue: 0.10, alpha: 0.85))
        ctx.setLineWidth(s * 0.015); ctx.setLineCap(.round)
        for dir: CGFloat in [-1, 1] {
            let bx = cx + dir * headR * 0.34
            ctx.move(to: CGPoint(x: bx + dir * headR * 0.14, y: eyeY + headR * 0.30))
            ctx.addLine(to: CGPoint(x: bx - dir * headR * 0.10, y: eyeY + headR * 0.24))
        }
        ctx.strokePath(); ctx.setLineCap(.butt)

        // Stern flat mouth
        let my = headY - headR * 0.42
        ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
        ctx.setLineWidth(max(s * 0.016, 1.2)); ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: cx - headR * 0.15, y: my))
        ctx.addLine(to: CGPoint(x: cx + headR * 0.15, y: my))
        ctx.strokePath()
        // Downturn at corners
        for dir: CGFloat in [-1, 1] {
            ctx.move(to: CGPoint(x: cx + dir * headR * 0.15, y: my))
            ctx.addLine(to: CGPoint(x: cx + dir * headR * 0.18, y: my - headR * 0.04))
        }
        ctx.strokePath(); ctx.setLineCap(.butt)
    }

    // MARK: - Jim Halpert

    private static func drawJim(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2, headR = s * 0.32, headY = s * 0.61
        let bodyW = s * 0.26, bodyH = s * 0.20, bodyY = s * 0.25
        let skin = CGColor(red: 0.93, green: 0.81, blue: 0.71, alpha: 1)
        let whiteShirt = CGColor(gray: 0.95, alpha: 1)
        let hair = CGColor(red: 0.30, green: 0.20, blue: 0.12, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW, h: s * 0.04)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: CGColor(gray: 0.18, alpha: 1), size: s)
        outlinedEllipse(ctx, rect: CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH), fill: whiteShirt, outline: ol)
        // Open collar — skin showing
        ctx.setFillColor(skin)
        ctx.move(to: CGPoint(x: cx - bodyW * 0.10, y: bodyY + bodyH * 0.42))
        ctx.addLine(to: CGPoint(x: cx + bodyW * 0.10, y: bodyY + bodyH * 0.42))
        ctx.addLine(to: CGPoint(x: cx, y: bodyY + bodyH * 0.10))
        ctx.fillPath()
        // Loosened tie — sits low, slightly off-center
        let tieX = cx + s * 0.008
        ctx.setFillColor(CGColor(red: 0.38, green: 0.50, blue: 0.70, alpha: 1))
        let tw = s * 0.018
        ctx.move(to: CGPoint(x: tieX - tw, y: bodyY + bodyH * 0.22))
        ctx.addLine(to: CGPoint(x: tieX + tw, y: bodyY + bodyH * 0.20))
        ctx.addLine(to: CGPoint(x: tieX + tw * 0.7, y: bodyY - bodyH * 0.06))
        ctx.addLine(to: CGPoint(x: tieX, y: bodyY - bodyH * 0.15))
        ctx.addLine(to: CGPoint(x: tieX - tw * 0.5, y: bodyY - bodyH * 0.06))
        ctx.fillPath()
        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: whiteShirt, size: s)

        // Head
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: skin, outline: ol)
        headHighlight(ctx, cx: cx, headY: headY, headR: headR)

        // Tousled floppy hair — thick, swooping to the right
        ctx.saveGState()
        ctx.addEllipse(in: headRect); ctx.clip()
        ctx.setFillColor(hair)
        ctx.fill(CGRect(x: cx - headR, y: headY + headR * 0.15, width: headR * 2, height: headR * 0.90))
        ctx.restoreGState()
        // Big swoopy fringe
        ctx.setFillColor(hair)
        ctx.move(to: CGPoint(x: cx - headR * 0.70, y: headY + headR * 0.42))
        ctx.addQuadCurve(to: CGPoint(x: cx + headR * 0.85, y: headY + headR * 0.30),
                         control: CGPoint(x: cx + headR * 0.10, y: headY + headR * 0.90))
        ctx.addLine(to: CGPoint(x: cx + headR * 0.60, y: headY + headR * 0.60))
        ctx.addQuadCurve(to: CGPoint(x: cx - headR * 0.40, y: headY + headR * 0.62),
                         control: CGPoint(x: cx + headR * 0.05, y: headY + headR * 0.55))
        ctx.fillPath()
        // Extra tuft sticking up
        ctx.move(to: CGPoint(x: cx + headR * 0.20, y: headY + headR * 0.68))
        ctx.addQuadCurve(to: CGPoint(x: cx + headR * 0.50, y: headY + headR * 0.78),
                         control: CGPoint(x: cx + headR * 0.40, y: headY + headR * 0.95))
        ctx.addLine(to: CGPoint(x: cx + headR * 0.35, y: headY + headR * 0.62))
        ctx.fillPath()

        // Eyes
        let eyeY = headY - headR * 0.05
        drawEyes(ctx, cx: cx, eyeY: eyeY, spacing: headR * 0.36, ew: headR * 0.24, eh: headR * 0.30, skin: skin)

        // Eyebrows — left normal, right raised (camera look)
        ctx.setStrokeColor(CGColor(red: 0.25, green: 0.16, blue: 0.08, alpha: 0.7))
        ctx.setLineWidth(s * 0.012); ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: cx - headR * 0.48, y: eyeY + headR * 0.28))
        ctx.addLine(to: CGPoint(x: cx - headR * 0.24, y: eyeY + headR * 0.30))
        ctx.strokePath()
        ctx.move(to: CGPoint(x: cx + headR * 0.24, y: eyeY + headR * 0.30))
        ctx.addLine(to: CGPoint(x: cx + headR * 0.48, y: eyeY + headR * 0.36))
        ctx.strokePath(); ctx.setLineCap(.butt)

        // Smirk — flat left, curves up right
        let my = headY - headR * 0.42
        ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
        ctx.setLineWidth(max(s * 0.016, 1.2)); ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: cx - headR * 0.15, y: my))
        ctx.addLine(to: CGPoint(x: cx, y: my))
        ctx.strokePath()
        ctx.move(to: CGPoint(x: cx, y: my))
        ctx.addQuadCurve(to: CGPoint(x: cx + headR * 0.18, y: my + headR * 0.07),
                         control: CGPoint(x: cx + headR * 0.12, y: my + headR * 0.01))
        ctx.strokePath(); ctx.setLineCap(.butt)
    }

    // MARK: - Pam Beesly

    private static func drawPam(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2, headR = s * 0.32, headY = s * 0.61
        let bodyW = s * 0.25, bodyH = s * 0.20, bodyY = s * 0.25
        let skin = CGColor(red: 0.94, green: 0.83, blue: 0.73, alpha: 1)
        let cardigan = CGColor(red: 0.78, green: 0.60, blue: 0.62, alpha: 1)
        let blouse = CGColor(red: 0.90, green: 0.86, blue: 0.82, alpha: 1)
        let hairColor = CGColor(red: 0.52, green: 0.28, blue: 0.15, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW, h: s * 0.04)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: CGColor(red: 0.50, green: 0.38, blue: 0.32, alpha: 1), size: s)

        // Hair flowing behind body
        ctx.setFillColor(hairColor)
        for dir: CGFloat in [-1, 1] {
            let hx = cx + dir * bodyW * 0.30
            ctx.move(to: CGPoint(x: hx, y: headY - headR * 0.10))
            ctx.addQuadCurve(to: CGPoint(x: hx + dir * headR * 0.20, y: bodyY + bodyH * 0.15),
                             control: CGPoint(x: hx + dir * headR * 0.30, y: headY - headR * 0.50))
            ctx.addLine(to: CGPoint(x: hx - dir * headR * 0.10, y: bodyY))
            ctx.fillPath()
        }

        outlinedEllipse(ctx, rect: CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH), fill: cardigan, outline: ol)
        // Blouse under cardigan
        ctx.setFillColor(blouse)
        ctx.move(to: CGPoint(x: cx - bodyW * 0.10, y: bodyY + bodyH * 0.35))
        ctx.addLine(to: CGPoint(x: cx + bodyW * 0.10, y: bodyY + bodyH * 0.35))
        ctx.addLine(to: CGPoint(x: cx + bodyW * 0.06, y: bodyY - bodyH * 0.10))
        ctx.addLine(to: CGPoint(x: cx - bodyW * 0.06, y: bodyY - bodyH * 0.10))
        ctx.fillPath()
        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: cardigan, size: s)

        // Head
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: skin, outline: ol)
        headHighlight(ctx, cx: cx, headY: headY, headR: headR)

        // Auburn wavy hair — frame face, center part
        ctx.saveGState()
        ctx.addEllipse(in: headRect); ctx.clip()
        ctx.setFillColor(hairColor)
        ctx.fill(CGRect(x: cx - headR, y: headY + headR * 0.22, width: headR * 2, height: headR * 0.82))
        ctx.setFillColor(skin)
        ctx.fillEllipse(in: CGRect(x: cx - headR * 0.06, y: headY + headR * 0.52, width: headR * 0.12, height: headR * 0.30))
        ctx.restoreGState()
        // Wavy strands on sides
        ctx.setStrokeColor(CGColor(red: 0.62, green: 0.36, blue: 0.20, alpha: 0.6))
        ctx.setLineWidth(s * 0.007); ctx.setLineCap(.round)
        for dir: CGFloat in [-1, 1] {
            let wx = cx + dir * headR * 0.50
            ctx.move(to: CGPoint(x: wx, y: headY + headR * 0.10))
            ctx.addQuadCurve(to: CGPoint(x: wx + dir * headR * 0.15, y: headY - headR * 0.30),
                             control: CGPoint(x: wx + dir * headR * 0.22, y: headY - headR * 0.05))
        }
        ctx.strokePath(); ctx.setLineCap(.butt)

        // Warm eyes
        let eyeY = headY - headR * 0.05
        drawEyes(ctx, cx: cx, eyeY: eyeY, spacing: headR * 0.35, ew: headR * 0.22, eh: headR * 0.28, skin: skin)

        // Gentle smile
        let my = headY - headR * 0.40
        ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
        ctx.setLineWidth(max(s * 0.016, 1.2)); ctx.setLineCap(.round)
        ctx.addArc(center: CGPoint(x: cx, y: my + headR * 0.10),
                   radius: headR * 0.14,
                   startAngle: -.pi * 0.15, endAngle: -.pi * 0.85, clockwise: true)
        ctx.strokePath(); ctx.setLineCap(.butt)

        // Rosy cheeks
        ctx.setFillColor(CGColor(red: 0.90, green: 0.58, blue: 0.52, alpha: 0.25))
        for dir: CGFloat in [-1, 1] {
            let chX = cx + dir * headR * 0.44, chY = headY - headR * 0.22, chR = headR * 0.12
            ctx.fillEllipse(in: CGRect(x: chX - chR, y: chY - chR, width: chR * 2, height: chR * 2))
        }
    }

    // MARK: - Angela Martin

    private static func drawAngela(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2, headR = s * 0.30, headY = s * 0.58
        let bodyW = s * 0.22, bodyH = s * 0.18, bodyY = s * 0.25  // small frame
        let skin = CGColor(red: 0.95, green: 0.86, blue: 0.78, alpha: 1)
        let outfit = CGColor(red: 0.85, green: 0.80, blue: 0.72, alpha: 1)
        let blondeHair = CGColor(red: 0.90, green: 0.80, blue: 0.55, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW * 0.85, h: s * 0.03)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: CGColor(red: 0.48, green: 0.40, blue: 0.32, alpha: 1), size: s)
        outlinedEllipse(ctx, rect: CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH), fill: outfit, outline: ol)

        // Cross necklace
        ctx.setStrokeColor(CGColor(red: 0.78, green: 0.70, blue: 0.48, alpha: 1))
        ctx.setLineWidth(s * 0.007)
        let crY = bodyY + bodyH * 0.22
        ctx.move(to: CGPoint(x: cx, y: crY + s * 0.025))
        ctx.addLine(to: CGPoint(x: cx, y: crY - s * 0.015))
        ctx.strokePath()
        ctx.move(to: CGPoint(x: cx - s * 0.010, y: crY + s * 0.012))
        ctx.addLine(to: CGPoint(x: cx + s * 0.010, y: crY + s * 0.012))
        ctx.strokePath()

        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: outfit, size: s)

        // Head
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: skin, outline: ol)
        headHighlight(ctx, cx: cx, headY: headY, headR: headR)

        // Tight pulled-back blonde hair
        ctx.saveGState()
        ctx.addEllipse(in: headRect); ctx.clip()
        ctx.setFillColor(blondeHair)
        ctx.fill(CGRect(x: cx - headR, y: headY + headR * 0.40, width: headR * 2, height: headR * 0.65))
        ctx.restoreGState()
        // Bun on top
        let bunR = headR * 0.20
        outlinedEllipse(ctx, rect: CGRect(x: cx - bunR, y: headY + headR + bunR * 0.3, width: bunR * 2, height: bunR * 2), fill: blondeHair, outline: ol)

        // Narrow disapproving eyes
        let eyeY = headY - headR * 0.02
        drawEyes(ctx, cx: cx, eyeY: eyeY, spacing: headR * 0.32, ew: headR * 0.18, eh: headR * 0.20, skin: skin, halfLid: 0.40, pupilScale: 0.50)

        // Thin pursed mouth
        let my = headY - headR * 0.38
        ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
        ctx.setLineWidth(max(s * 0.013, 1.0)); ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: cx - headR * 0.08, y: my))
        ctx.addLine(to: CGPoint(x: cx + headR * 0.08, y: my))
        ctx.strokePath(); ctx.setLineCap(.butt)
    }

    // MARK: - Kevin Malone

    private static func drawKevin(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2, headR = s * 0.38, headY = s * 0.62
        let bodyW = s * 0.34, bodyH = s * 0.24, bodyY = s * 0.24  // wide
        let skin = CGColor(red: 0.92, green: 0.80, blue: 0.70, alpha: 1)
        let cardigan = CGColor(red: 0.32, green: 0.50, blue: 0.32, alpha: 1)
        let shirt = CGColor(gray: 0.90, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW * 1.1, h: s * 0.04)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: CGColor(gray: 0.18, alpha: 1), size: s)
        outlinedEllipse(ctx, rect: CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH), fill: cardigan, outline: ol)
        // Shirt showing
        ctx.setFillColor(shirt)
        ctx.move(to: CGPoint(x: cx - bodyW * 0.12, y: bodyY + bodyH * 0.36))
        ctx.addLine(to: CGPoint(x: cx + bodyW * 0.12, y: bodyY + bodyH * 0.36))
        ctx.addLine(to: CGPoint(x: cx + bodyW * 0.08, y: bodyY - bodyH * 0.05))
        ctx.addLine(to: CGPoint(x: cx - bodyW * 0.08, y: bodyY - bodyH * 0.05))
        ctx.fillPath()
        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: cardigan, size: s)

        // Big round head
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: skin, outline: ol)
        headHighlight(ctx, cx: cx, headY: headY, headR: headR)

        // Bald — just faint stubble on sides
        ctx.setFillColor(CGColor(red: 0.38, green: 0.28, blue: 0.20, alpha: 0.18))
        ctx.saveGState()
        ctx.addEllipse(in: headRect); ctx.clip()
        ctx.fill(CGRect(x: cx - headR, y: headY - headR * 0.25, width: headR * 0.30, height: headR * 0.55))
        ctx.fill(CGRect(x: cx + headR * 0.70, y: headY - headR * 0.25, width: headR * 0.30, height: headR * 0.55))
        ctx.restoreGState()

        // Dopey half-lidded eyes
        let eyeY = headY - headR * 0.02
        drawEyes(ctx, cx: cx, eyeY: eyeY, spacing: headR * 0.38, ew: headR * 0.16, eh: headR * 0.20, skin: skin, halfLid: 0.45, pupilScale: 0.55)

        // Big open-mouth grin
        let my = headY - headR * 0.42, mw = headR * 0.38, mh = headR * 0.20
        ctx.setFillColor(CGColor(red: 0.30, green: 0.08, blue: 0.06, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: cx - mw, y: my - mh, width: mw * 2, height: mh * 2))
        // Teeth
        ctx.setFillColor(CGColor(gray: 0.95, alpha: 1))
        ctx.fill(CGRect(x: cx - mw * 0.75, y: my + mh * 0.05, width: mw * 1.50, height: mh * 0.65))
    }

    // MARK: - Stanley Hudson

    private static func drawStanley(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2, headR = s * 0.34, headY = s * 0.63
        let bodyW = s * 0.30, bodyH = s * 0.22, bodyY = s * 0.25
        let skin = CGColor(red: 0.42, green: 0.30, blue: 0.22, alpha: 1)
        let sweater = CGColor(red: 0.52, green: 0.42, blue: 0.30, alpha: 1)
        let whiteShirt = CGColor(gray: 0.92, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW, h: s * 0.04)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: CGColor(gray: 0.15, alpha: 1), size: s)
        outlinedEllipse(ctx, rect: CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH), fill: sweater, outline: ol)
        // White collar
        ctx.setFillColor(whiteShirt)
        ctx.move(to: CGPoint(x: cx - bodyW * 0.20, y: bodyY + bodyH * 0.42))
        ctx.addLine(to: CGPoint(x: cx + bodyW * 0.20, y: bodyY + bodyH * 0.42))
        ctx.addLine(to: CGPoint(x: cx + bodyW * 0.12, y: bodyY + bodyH * 0.22))
        ctx.addLine(to: CGPoint(x: cx - bodyW * 0.12, y: bodyY + bodyH * 0.22))
        ctx.fillPath()
        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: whiteShirt, size: s)

        // Head
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: skin, outline: ol)
        headHighlight(ctx, cx: cx, headY: headY, headR: headR)

        // Bald — gray patches on sides
        ctx.setFillColor(CGColor(gray: 0.42, alpha: 0.22))
        ctx.saveGState()
        ctx.addEllipse(in: headRect); ctx.clip()
        ctx.fill(CGRect(x: cx - headR, y: headY - headR * 0.28, width: headR * 0.35, height: headR * 0.60))
        ctx.fill(CGRect(x: cx + headR * 0.65, y: headY - headR * 0.28, width: headR * 0.35, height: headR * 0.60))
        ctx.restoreGState()

        // Round glasses
        let gy = headY + headR * 0.02
        drawRoundGlasses(ctx, cx: cx, gy: gy, headR: headR, s: s)

        // Half-lidded unamused eyes
        let eyeY = headY - headR * 0.0
        drawEyes(ctx, cx: cx, eyeY: eyeY, spacing: headR * 0.33, ew: headR * 0.17, eh: headR * 0.20, skin: skin, halfLid: 0.50, pupilScale: 0.50)

        // Gray mustache
        ctx.setFillColor(CGColor(gray: 0.48, alpha: 1))
        let mustY = headY - headR * 0.25
        ctx.move(to: CGPoint(x: cx - headR * 0.32, y: mustY))
        ctx.addQuadCurve(to: CGPoint(x: cx, y: mustY + headR * 0.05),
                         control: CGPoint(x: cx - headR * 0.15, y: mustY + headR * 0.10))
        ctx.addQuadCurve(to: CGPoint(x: cx + headR * 0.32, y: mustY),
                         control: CGPoint(x: cx + headR * 0.15, y: mustY + headR * 0.10))
        ctx.addLine(to: CGPoint(x: cx + headR * 0.28, y: mustY - headR * 0.04))
        ctx.addQuadCurve(to: CGPoint(x: cx - headR * 0.28, y: mustY - headR * 0.04),
                         control: CGPoint(x: cx, y: mustY - headR * 0.01))
        ctx.fillPath()

        // Grumpy frown
        let my = headY - headR * 0.46
        ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
        ctx.setLineWidth(max(s * 0.016, 1.2)); ctx.setLineCap(.round)
        ctx.addArc(center: CGPoint(x: cx, y: my - headR * 0.06),
                   radius: headR * 0.12,
                   startAngle: .pi * 0.20, endAngle: .pi * 0.80, clockwise: false)
        ctx.strokePath(); ctx.setLineCap(.butt)
    }

    // MARK: - Creed Bratton

    private static func drawCreed(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2, headR = s * 0.32, headY = s * 0.61
        let bodyW = s * 0.26, bodyH = s * 0.20, bodyY = s * 0.25
        let skin = CGColor(red: 0.88, green: 0.78, blue: 0.70, alpha: 1)
        let shirt = CGColor(red: 0.58, green: 0.56, blue: 0.52, alpha: 1)
        let whiteHair = CGColor(gray: 0.82, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW, h: s * 0.04)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: CGColor(gray: 0.20, alpha: 1), size: s)
        outlinedEllipse(ctx, rect: CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH), fill: shirt, outline: ol)
        // Open collar
        ctx.setFillColor(skin)
        ctx.move(to: CGPoint(x: cx - bodyW * 0.08, y: bodyY + bodyH * 0.40))
        ctx.addLine(to: CGPoint(x: cx + bodyW * 0.08, y: bodyY + bodyH * 0.40))
        ctx.addLine(to: CGPoint(x: cx, y: bodyY + bodyH * 0.12))
        ctx.fillPath()
        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: shirt, size: s)

        // Head
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: skin, outline: ol)
        headHighlight(ctx, cx: cx, headY: headY, headR: headR)

        // Sparse white hair on sides
        ctx.saveGState()
        ctx.addEllipse(in: headRect); ctx.clip()
        ctx.setFillColor(whiteHair)
        ctx.fill(CGRect(x: cx - headR, y: headY - headR * 0.10, width: headR * 0.25, height: headR * 0.40))
        ctx.fill(CGRect(x: cx + headR * 0.75, y: headY - headR * 0.10, width: headR * 0.25, height: headR * 0.40))
        ctx.restoreGState()
        // Wispy tufts
        ctx.setStrokeColor(whiteHair)
        ctx.setLineWidth(s * 0.006); ctx.setLineCap(.round)
        for dir: CGFloat in [-1, 1] {
            let bx = cx + dir * headR * 0.88, by = headY + headR * 0.10
            ctx.move(to: CGPoint(x: bx, y: by))
            ctx.addLine(to: CGPoint(x: bx + dir * s * 0.025, y: by + s * 0.02))
            ctx.move(to: CGPoint(x: bx, y: by - headR * 0.12))
            ctx.addLine(to: CGPoint(x: bx + dir * s * 0.02, y: by - headR * 0.08))
        }
        ctx.strokePath(); ctx.setLineCap(.butt)

        // Wrinkles
        ctx.setStrokeColor(CGColor(red: 0.72, green: 0.62, blue: 0.55, alpha: 0.35))
        ctx.setLineWidth(s * 0.004)
        ctx.move(to: CGPoint(x: cx - headR * 0.28, y: headY + headR * 0.28))
        ctx.addLine(to: CGPoint(x: cx + headR * 0.28, y: headY + headR * 0.30))
        ctx.move(to: CGPoint(x: cx - headR * 0.22, y: headY + headR * 0.22))
        ctx.addLine(to: CGPoint(x: cx + headR * 0.22, y: headY + headR * 0.23))
        ctx.strokePath()

        // Unfocused eyes — pupils looking different directions
        let eyeY = headY - headR * 0.05
        drawEyes(ctx, cx: cx, eyeY: eyeY, spacing: headR * 0.36, ew: headR * 0.22, eh: headR * 0.28, skin: skin,
                 pupilOffsets: [(-headR * 0.04, headR * 0.02), (headR * 0.05, -headR * 0.03)])

        // Mysterious half-smile — asymmetric
        let my = headY - headR * 0.42
        ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
        ctx.setLineWidth(max(s * 0.015, 1.2)); ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: cx - headR * 0.14, y: my - headR * 0.02))
        ctx.addLine(to: CGPoint(x: cx, y: my))
        ctx.strokePath()
        ctx.move(to: CGPoint(x: cx, y: my))
        ctx.addQuadCurve(to: CGPoint(x: cx + headR * 0.16, y: my + headR * 0.06),
                         control: CGPoint(x: cx + headR * 0.10, y: my + headR * 0.01))
        ctx.strokePath(); ctx.setLineCap(.butt)
    }
}
