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

    /// Tracks which character is assigned to each active session to avoid duplicates.
    private static var assignments: [String: Character] = [:]

    /// Remove assignment when a session departs.
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

    /// Preferred character from hash (ignoring dedup).
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
            result = preferred  // all characters exhausted, allow duplicate
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

    // MARK: - Michael Scott

    private static func drawMichael(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2
        let headR = s * 0.30
        let headY = s * 0.60
        let bodyW = s * 0.28, bodyH = s * 0.22
        let bodyY = s * 0.25

        let skin = CGColor(red: 0.92, green: 0.80, blue: 0.70, alpha: 1)
        let suit = CGColor(red: 0.12, green: 0.15, blue: 0.28, alpha: 1)
        let shirt = CGColor(red: 0.55, green: 0.65, blue: 0.82, alpha: 1)
        let tie = CGColor(red: 0.78, green: 0.18, blue: 0.18, alpha: 1)
        let shoe = CGColor(gray: 0.15, alpha: 1)
        let hair = CGColor(red: 0.32, green: 0.22, blue: 0.14, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW, h: s * 0.04)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: shoe, size: s)

        // Body — dark navy suit
        let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH)
        outlinedEllipse(ctx, rect: bodyRect, fill: suit, outline: ol)

        // Shirt collar V
        ctx.setFillColor(shirt)
        ctx.move(to: CGPoint(x: cx - bodyW * 0.15, y: bodyY + bodyH * 0.4))
        ctx.addLine(to: CGPoint(x: cx + bodyW * 0.15, y: bodyY + bodyH * 0.4))
        ctx.addLine(to: CGPoint(x: cx, y: bodyY + bodyH * 0.05))
        ctx.fillPath()

        // Red tie
        ctx.setFillColor(tie)
        let tieW = s * 0.025
        ctx.move(to: CGPoint(x: cx - tieW, y: bodyY + bodyH * 0.35))
        ctx.addLine(to: CGPoint(x: cx + tieW, y: bodyY + bodyH * 0.35))
        ctx.addLine(to: CGPoint(x: cx + tieW * 0.7, y: bodyY - bodyH * 0.1))
        ctx.addLine(to: CGPoint(x: cx, y: bodyY - bodyH * 0.2))
        ctx.addLine(to: CGPoint(x: cx - tieW * 0.7, y: bodyY - bodyH * 0.1))
        ctx.fillPath()

        // Left arm (suit)
        let lax = cx - (bodyW / 2 + s * 0.04)
        let lay = bodyY + bodyH * 0.05
        ctx.saveGState()
        ctx.translateBy(x: lax, y: lay)
        ctx.rotate(by: -0.3)
        outlinedEllipse(ctx, rect: CGRect(x: -s * 0.03, y: -s * 0.055, width: s * 0.06, height: s * 0.11), fill: suit, outline: ol)
        ctx.restoreGState()

        // Right arm holding mug — angled inward
        let rax = cx + (bodyW / 2 + s * 0.02)
        let ray = bodyY + bodyH * 0.10
        ctx.saveGState()
        ctx.translateBy(x: rax, y: ray)
        ctx.rotate(by: 0.15)
        outlinedEllipse(ctx, rect: CGRect(x: -s * 0.03, y: -s * 0.055, width: s * 0.06, height: s * 0.11), fill: suit, outline: ol)
        ctx.restoreGState()

        // "World's Best Boss" mug
        let mugX = cx + bodyW * 0.52
        let mugY = bodyY + bodyH * 0.02
        let mugW = s * 0.065, mugH = s * 0.055
        // Mug body — white ceramic
        outlinedRoundRect(ctx, rect: CGRect(x: mugX - mugW / 2, y: mugY - mugH / 2, width: mugW, height: mugH),
                          fill: CGColor(gray: 0.95, alpha: 1), outline: ol * 0.8, radius: s * 0.008)
        // Mug handle
        ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
        ctx.setLineWidth(s * 0.01)
        ctx.addArc(center: CGPoint(x: mugX + mugW / 2, y: mugY),
                   radius: mugH * 0.30,
                   startAngle: -.pi * 0.4,
                   endAngle: .pi * 0.4,
                   clockwise: false)
        ctx.strokePath()
        // Red text on mug (tiny heart or line)
        ctx.setFillColor(CGColor(red: 0.8, green: 0.15, blue: 0.15, alpha: 1))
        ctx.fill(CGRect(x: mugX - mugW * 0.25, y: mugY - mugH * 0.1, width: mugW * 0.5, height: s * 0.006))
        ctx.fill(CGRect(x: mugX - mugW * 0.20, y: mugY + mugH * 0.05, width: mugW * 0.4, height: s * 0.006))

        // Head
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: skin, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // Hair — gelled up with volume, combed back with side part
        ctx.saveGState()
        ctx.addEllipse(in: headRect)
        ctx.clip()
        ctx.setFillColor(hair)
        ctx.fill(CGRect(x: cx - headR, y: headY + headR * 0.25, width: headR * 2, height: headR * 0.80))
        // Side part — lighter gap on left
        ctx.setFillColor(CGColor(red: 0.40, green: 0.30, blue: 0.20, alpha: 1))
        ctx.fill(CGRect(x: cx - headR * 0.15, y: headY + headR * 0.55, width: headR * 0.05, height: headR * 0.35))
        ctx.restoreGState()
        // Gelled-up front volume — extra hair tuft above forehead
        ctx.setFillColor(hair)
        ctx.move(to: CGPoint(x: cx - headR * 0.6, y: headY + headR * 0.55))
        ctx.addQuadCurve(to: CGPoint(x: cx + headR * 0.5, y: headY + headR * 0.50),
                         control: CGPoint(x: cx, y: headY + headR * 1.12))
        ctx.addLine(to: CGPoint(x: cx + headR * 0.5, y: headY + headR * 0.40))
        ctx.addLine(to: CGPoint(x: cx - headR * 0.6, y: headY + headR * 0.42))
        ctx.fillPath()
        // Slight receding at temples
        ctx.setFillColor(skin)
        for dir: CGFloat in [-1, 1] {
            ctx.fillEllipse(in: CGRect(x: cx + dir * headR * 0.55 - headR * 0.12,
                                       y: headY + headR * 0.38,
                                       width: headR * 0.24, height: headR * 0.18))
        }

        // Slightly raised eyebrows (expressive)
        ctx.setStrokeColor(CGColor(red: 0.30, green: 0.20, blue: 0.12, alpha: 0.8))
        ctx.setLineWidth(s * 0.015)
        ctx.setLineCap(.round)
        for dir: CGFloat in [-1, 1] {
            let bx = cx + dir * headR * 0.35
            let by = headY + headR * 0.24
            ctx.move(to: CGPoint(x: bx - headR * 0.13, y: by - headR * 0.03))
            ctx.addQuadCurve(to: CGPoint(x: bx + headR * 0.13, y: by - headR * 0.01),
                             control: CGPoint(x: bx, y: by + headR * 0.06))
        }
        ctx.strokePath()
        ctx.setLineCap(.butt)

        // Wide eager eyes
        drawSimpleEyes(ctx, cx: cx, headY: headY, headR: headR, size: s, spacing: 0.35)

        // Goofy wide grin showing teeth
        let mouthY = headY - headR * 0.42
        let mouthW = headR * 0.38
        let mouthH = headR * 0.16
        ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: cx - mouthW, y: mouthY - mouthH, width: mouthW * 2, height: mouthH * 2))
        // Upper teeth row
        ctx.setFillColor(CGColor(gray: 0.96, alpha: 1))
        ctx.fill(CGRect(x: cx - mouthW * 0.75, y: mouthY, width: mouthW * 1.5, height: mouthH * 0.85))
        // Tooth dividers
        ctx.setStrokeColor(CGColor(gray: 0.82, alpha: 1))
        ctx.setLineWidth(s * 0.004)
        for offset: CGFloat in [-0.33, 0, 0.33] {
            let tx = cx + mouthW * offset
            ctx.move(to: CGPoint(x: tx, y: mouthY + mouthH * 0.8))
            ctx.addLine(to: CGPoint(x: tx, y: mouthY + mouthH * 0.05))
        }
        ctx.strokePath()
    }

    // MARK: - Dwight Schrute

    private static func drawDwight(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2
        let headR = s * 0.32
        let headY = s * 0.62
        let bodyW = s * 0.28, bodyH = s * 0.22
        let bodyY = s * 0.25

        let skin = CGColor(red: 0.92, green: 0.82, blue: 0.72, alpha: 1)
        let suitBrown = CGColor(red: 0.42, green: 0.32, blue: 0.18, alpha: 1)
        let mustardShirt = CGColor(red: 0.78, green: 0.68, blue: 0.22, alpha: 1)
        let beetTie = CGColor(red: 0.60, green: 0.10, blue: 0.15, alpha: 1)
        let shoe = CGColor(gray: 0.18, alpha: 1)
        let hair = CGColor(red: 0.35, green: 0.25, blue: 0.15, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW, h: s * 0.04)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: shoe, size: s)

        // Body — brown suit
        let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH)
        outlinedEllipse(ctx, rect: bodyRect, fill: suitBrown, outline: ol)

        // Mustard shirt collar
        ctx.setFillColor(mustardShirt)
        ctx.move(to: CGPoint(x: cx - bodyW * 0.18, y: bodyY + bodyH * 0.4))
        ctx.addLine(to: CGPoint(x: cx + bodyW * 0.18, y: bodyY + bodyH * 0.4))
        ctx.addLine(to: CGPoint(x: cx, y: bodyY + bodyH * 0.05))
        ctx.fillPath()

        // Beet-red tie
        ctx.setFillColor(beetTie)
        let tieW = s * 0.022
        ctx.move(to: CGPoint(x: cx - tieW, y: bodyY + bodyH * 0.32))
        ctx.addLine(to: CGPoint(x: cx + tieW, y: bodyY + bodyH * 0.32))
        ctx.addLine(to: CGPoint(x: cx + tieW * 0.6, y: bodyY - bodyH * 0.1))
        ctx.addLine(to: CGPoint(x: cx, y: bodyY - bodyH * 0.2))
        ctx.addLine(to: CGPoint(x: cx - tieW * 0.6, y: bodyY - bodyH * 0.1))
        ctx.fillPath()

        // ID badge clipped to pocket — Dunder Mifflin
        let badgeX = cx + bodyW * 0.22
        let badgeY = bodyY + bodyH * 0.08
        let badgeW = s * 0.04, badgeH = s * 0.05
        // Lanyard line from neck
        ctx.setStrokeColor(CGColor(red: 0.15, green: 0.30, blue: 0.55, alpha: 1))
        ctx.setLineWidth(s * 0.006)
        ctx.move(to: CGPoint(x: cx + bodyW * 0.08, y: bodyY + bodyH * 0.40))
        ctx.addLine(to: CGPoint(x: badgeX, y: badgeY + badgeH / 2))
        ctx.strokePath()
        // Badge card
        outlinedRoundRect(ctx, rect: CGRect(x: badgeX - badgeW / 2, y: badgeY - badgeH / 2, width: badgeW, height: badgeH),
                          fill: CGColor(gray: 0.95, alpha: 1), outline: ol * 0.6, radius: s * 0.004)
        // Blue stripe on badge
        ctx.setFillColor(CGColor(red: 0.15, green: 0.30, blue: 0.55, alpha: 1))
        ctx.fill(CGRect(x: badgeX - badgeW * 0.35, y: badgeY + badgeH * 0.15, width: badgeW * 0.7, height: badgeH * 0.15))

        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: suitBrown, size: s)

        // Head — slightly large forehead
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: skin, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // Center-parted bowl cut with pointed sideburns
        ctx.saveGState()
        ctx.addEllipse(in: headRect)
        ctx.clip()
        ctx.setFillColor(hair)
        // Full hair covering top
        ctx.fill(CGRect(x: cx - headR, y: headY + headR * 0.10, width: headR * 2, height: headR * 0.95))
        // Center part — skin showing through
        ctx.setFillColor(skin)
        ctx.move(to: CGPoint(x: cx - headR * 0.03, y: headY + headR * 1.0))
        ctx.addLine(to: CGPoint(x: cx + headR * 0.03, y: headY + headR * 1.0))
        ctx.addLine(to: CGPoint(x: cx + headR * 0.08, y: headY + headR * 0.50))
        ctx.addLine(to: CGPoint(x: cx - headR * 0.08, y: headY + headR * 0.50))
        ctx.fillPath()
        // Bowl cut fringe — rounded bottom edge, sits low on forehead
        ctx.setFillColor(skin)
        ctx.fillEllipse(in: CGRect(x: cx - headR * 1.2, y: headY - headR * 0.20, width: headR * 2.4, height: headR * 0.52))
        ctx.restoreGState()
        // Pointed sideburns extending below head circle
        ctx.setFillColor(hair)
        for dir: CGFloat in [-1, 1] {
            let sbX = cx + dir * headR * 0.82
            ctx.move(to: CGPoint(x: sbX - headR * 0.08, y: headY + headR * 0.05))
            ctx.addLine(to: CGPoint(x: sbX + headR * 0.08, y: headY + headR * 0.05))
            ctx.addLine(to: CGPoint(x: sbX + headR * 0.03, y: headY - headR * 0.22))
            ctx.addLine(to: CGPoint(x: sbX - headR * 0.03, y: headY - headR * 0.22))
            ctx.fillPath()
        }

        // Thick rectangular wire-frame glasses
        ctx.setStrokeColor(CGColor(gray: 0.15, alpha: 1))
        ctx.setLineWidth(s * 0.02)
        for dir: CGFloat in [-1, 1] {
            let gx = cx + dir * headR * 0.33
            let gy = headY + headR * 0.0
            let gw = headR * 0.30, gh = headR * 0.20
            ctx.stroke(CGRect(x: gx - gw, y: gy - gh, width: gw * 2, height: gh * 2))
        }
        // Bridge
        ctx.setLineWidth(s * 0.015)
        ctx.move(to: CGPoint(x: cx - headR * 0.03, y: headY + headR * 0.02))
        ctx.addLine(to: CGPoint(x: cx + headR * 0.03, y: headY + headR * 0.02))
        ctx.strokePath()
        // Temple arms extending to sides
        for dir: CGFloat in [-1, 1] {
            ctx.move(to: CGPoint(x: cx + dir * (headR * 0.33 + headR * 0.30), y: headY))
            ctx.addLine(to: CGPoint(x: cx + dir * headR * 0.82, y: headY - headR * 0.02))
        }
        ctx.strokePath()

        // Squinting intense eyes — smaller, narrower
        let eyeY = headY - headR * 0.02
        let sp = headR * 0.33
        let ew = headR * 0.22, eh = headR * 0.18
        for dir: CGFloat in [-1, 1] {
            let ex = cx + dir * sp
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex - ew - 1.5, y: eyeY - eh - 1.5, width: (ew + 1.5) * 2, height: (eh + 1.5) * 2))
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex - ew, y: eyeY - eh, width: ew * 2, height: eh * 2))
            // Intense small pupils
            let pw = ew * 0.50, ph = eh * 0.55
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex - pw, y: eyeY - ph, width: pw * 2, height: ph * 2))
            let hlR = ew * 0.25
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex + ew * 0.15 - hlR / 2, y: eyeY + eh * 0.2 - hlR / 2, width: hlR, height: hlR))
            // Heavy upper eyelid — squinting look
            ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
            ctx.setLineWidth(s * 0.012)
            ctx.move(to: CGPoint(x: ex - ew * 0.9, y: eyeY + eh * 0.3))
            ctx.addQuadCurve(to: CGPoint(x: ex + ew * 0.9, y: eyeY + eh * 0.3),
                             control: CGPoint(x: ex, y: eyeY + eh * 0.75))
            ctx.strokePath()
        }

        // Angry/intense eyebrows — angled down toward center
        ctx.setStrokeColor(CGColor(red: 0.30, green: 0.20, blue: 0.12, alpha: 0.9))
        ctx.setLineWidth(s * 0.016)
        ctx.setLineCap(.round)
        for dir: CGFloat in [-1, 1] {
            let bx = cx + dir * headR * 0.33
            let by = headY + headR * 0.22
            ctx.move(to: CGPoint(x: bx + dir * headR * 0.15, y: by + headR * 0.06))
            ctx.addLine(to: CGPoint(x: bx - dir * headR * 0.10, y: by - headR * 0.02))
        }
        ctx.strokePath()
        ctx.setLineCap(.butt)

        // Stern flat mouth with slight downturn
        ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
        ctx.setLineWidth(max(s * 0.016, 1.2))
        ctx.setLineCap(.round)
        let mouthY = headY - headR * 0.42
        ctx.move(to: CGPoint(x: cx - headR * 0.16, y: mouthY))
        ctx.addLine(to: CGPoint(x: cx + headR * 0.16, y: mouthY))
        ctx.strokePath()
        ctx.setLineWidth(max(s * 0.012, 1.0))
        ctx.move(to: CGPoint(x: cx - headR * 0.16, y: mouthY))
        ctx.addLine(to: CGPoint(x: cx - headR * 0.19, y: mouthY - headR * 0.04))
        ctx.move(to: CGPoint(x: cx + headR * 0.16, y: mouthY))
        ctx.addLine(to: CGPoint(x: cx + headR * 0.19, y: mouthY - headR * 0.04))
        ctx.strokePath()
        ctx.setLineCap(.butt)
    }

    // MARK: - Jim Halpert

    private static func drawJim(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2
        let headR = s * 0.30
        let headY = s * 0.60
        let bodyW = s * 0.26, bodyH = s * 0.20
        let bodyY = s * 0.25

        let skin = CGColor(red: 0.92, green: 0.80, blue: 0.70, alpha: 1)
        let whiteShirt = CGColor(gray: 0.95, alpha: 1)
        let looseTie = CGColor(red: 0.40, green: 0.52, blue: 0.72, alpha: 1)
        let shoe = CGColor(gray: 0.18, alpha: 1)
        let hair = CGColor(red: 0.35, green: 0.25, blue: 0.15, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW, h: s * 0.04)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: shoe, size: s)

        // Body — white shirt, slightly untucked
        let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH)
        outlinedEllipse(ctx, rect: bodyRect, fill: whiteShirt, outline: ol)

        // Open collar — wider V showing more skin (casual)
        ctx.setFillColor(skin)
        ctx.move(to: CGPoint(x: cx - bodyW * 0.12, y: bodyY + bodyH * 0.42))
        ctx.addLine(to: CGPoint(x: cx + bodyW * 0.12, y: bodyY + bodyH * 0.42))
        ctx.addLine(to: CGPoint(x: cx, y: bodyY + bodyH * 0.05))
        ctx.fillPath()

        // Loosened blue tie — pulled down, off-center and askew
        ctx.setFillColor(looseTie)
        let tieX = cx + s * 0.01
        let tieW = s * 0.02
        // Tie knot sits lower (loosened)
        ctx.move(to: CGPoint(x: tieX - tieW * 1.2, y: bodyY + bodyH * 0.22))
        ctx.addLine(to: CGPoint(x: tieX + tieW * 1.2, y: bodyY + bodyH * 0.20))
        ctx.addLine(to: CGPoint(x: tieX + tieW * 0.8, y: bodyY - bodyH * 0.08))
        ctx.addLine(to: CGPoint(x: tieX, y: bodyY - bodyH * 0.18))
        ctx.addLine(to: CGPoint(x: tieX - tieW * 0.5, y: bodyY - bodyH * 0.08))
        ctx.fillPath()

        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: whiteShirt, size: s)

        // Head
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: skin, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // Tousled floppy hair — messy layers swooping right
        ctx.saveGState()
        ctx.addEllipse(in: headRect)
        ctx.clip()
        ctx.setFillColor(hair)
        ctx.fill(CGRect(x: cx - headR, y: headY + headR * 0.18, width: headR * 2, height: headR * 0.88))
        ctx.restoreGState()
        // Main swoopy fringe — thick and tousled, curves to the right
        ctx.setFillColor(hair)
        ctx.move(to: CGPoint(x: cx - headR * 0.75, y: headY + headR * 0.42))
        ctx.addQuadCurve(to: CGPoint(x: cx + headR * 0.85, y: headY + headR * 0.28),
                         control: CGPoint(x: cx + headR * 0.1, y: headY + headR * 0.80))
        ctx.addLine(to: CGPoint(x: cx + headR * 0.55, y: headY + headR * 0.68))
        ctx.addQuadCurve(to: CGPoint(x: cx - headR * 0.35, y: headY + headR * 0.68),
                         control: CGPoint(x: cx + headR * 0.05, y: headY + headR * 0.58))
        ctx.fillPath()
        // Second layer — shorter tuft over the first
        ctx.move(to: CGPoint(x: cx - headR * 0.5, y: headY + headR * 0.52))
        ctx.addQuadCurve(to: CGPoint(x: cx + headR * 0.65, y: headY + headR * 0.38),
                         control: CGPoint(x: cx + headR * 0.05, y: headY + headR * 0.78))
        ctx.addLine(to: CGPoint(x: cx + headR * 0.40, y: headY + headR * 0.60))
        ctx.addLine(to: CGPoint(x: cx - headR * 0.2, y: headY + headR * 0.62))
        ctx.fillPath()
        // Stray hair piece sticking up
        ctx.move(to: CGPoint(x: cx + headR * 0.15, y: headY + headR * 0.72))
        ctx.addQuadCurve(to: CGPoint(x: cx + headR * 0.45, y: headY + headR * 0.82),
                         control: CGPoint(x: cx + headR * 0.35, y: headY + headR * 1.0))
        ctx.addLine(to: CGPoint(x: cx + headR * 0.35, y: headY + headR * 0.68))
        ctx.fillPath()

        // Eyes — left normal, right with raised eyebrow
        drawSimpleEyes(ctx, cx: cx, headY: headY, headR: headR, size: s, spacing: 0.35)

        // Eyebrows — left normal, right raised (signature look-at-camera)
        ctx.setStrokeColor(CGColor(red: 0.30, green: 0.20, blue: 0.12, alpha: 0.8))
        ctx.setLineWidth(s * 0.014)
        ctx.setLineCap(.round)
        // Left eyebrow — normal
        let lbx = cx - headR * 0.35, lby = headY + headR * 0.20
        ctx.move(to: CGPoint(x: lbx - headR * 0.12, y: lby))
        ctx.addLine(to: CGPoint(x: lbx + headR * 0.12, y: lby + headR * 0.02))
        ctx.strokePath()
        // Right eyebrow — raised high
        let rbx = cx + headR * 0.35, rby = headY + headR * 0.28
        ctx.move(to: CGPoint(x: rbx - headR * 0.12, y: rby - headR * 0.02))
        ctx.addQuadCurve(to: CGPoint(x: rbx + headR * 0.12, y: rby),
                         control: CGPoint(x: rbx, y: rby + headR * 0.08))
        ctx.strokePath()
        ctx.setLineCap(.butt)

        // Signature smirk — one-sided half-smile
        ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
        ctx.setLineWidth(max(s * 0.016, 1.2))
        ctx.setLineCap(.round)
        let mouthY = headY - headR * 0.40
        // Left side flat/slight downturn
        ctx.move(to: CGPoint(x: cx - headR * 0.16, y: mouthY - headR * 0.01))
        ctx.addLine(to: CGPoint(x: cx - headR * 0.02, y: mouthY))
        ctx.strokePath()
        // Right side curves up — the smirk
        ctx.move(to: CGPoint(x: cx - headR * 0.02, y: mouthY))
        ctx.addQuadCurve(to: CGPoint(x: cx + headR * 0.20, y: mouthY + headR * 0.08),
                         control: CGPoint(x: cx + headR * 0.12, y: mouthY + headR * 0.01))
        ctx.strokePath()
        ctx.setLineCap(.butt)
    }

    // MARK: - Pam Beesly

    private static func drawPam(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2
        let headR = s * 0.30
        let headY = s * 0.60
        let bodyW = s * 0.26, bodyH = s * 0.20
        let bodyY = s * 0.25

        let skin = CGColor(red: 0.93, green: 0.82, blue: 0.72, alpha: 1)
        let cardigan = CGColor(red: 0.82, green: 0.68, blue: 0.65, alpha: 1)
        let blouse = CGColor(red: 0.88, green: 0.85, blue: 0.80, alpha: 1)
        let shoe = CGColor(red: 0.55, green: 0.40, blue: 0.35, alpha: 1)
        let hairColor = CGColor(red: 0.55, green: 0.30, blue: 0.18, alpha: 1)
        let hairHighlight = CGColor(red: 0.65, green: 0.38, blue: 0.22, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW, h: s * 0.04)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: shoe, size: s)

        // Flowing curly hair behind body (drawn before body)
        for dir: CGFloat in [-1, 1] {
            let hx = cx + dir * bodyW * 0.35
            ctx.setFillColor(hairColor)
            // Main flowing wave
            ctx.move(to: CGPoint(x: hx, y: headY - headR * 0.15))
            ctx.addQuadCurve(to: CGPoint(x: hx + dir * headR * 0.25, y: bodyY + bodyH * 0.20),
                             control: CGPoint(x: hx + dir * headR * 0.35, y: headY - headR * 0.55))
            ctx.addQuadCurve(to: CGPoint(x: hx - dir * headR * 0.05, y: bodyY - bodyH * 0.05),
                             control: CGPoint(x: hx - dir * headR * 0.10, y: bodyY + bodyH * 0.10))
            ctx.addLine(to: CGPoint(x: hx - dir * headR * 0.15, y: headY - headR * 0.15))
            ctx.fillPath()
        }

        // Body — pink cardigan
        let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH)
        outlinedEllipse(ctx, rect: bodyRect, fill: cardigan, outline: ol)

        // Blouse showing under cardigan
        ctx.setFillColor(blouse)
        ctx.move(to: CGPoint(x: cx - bodyW * 0.12, y: bodyY + bodyH * 0.35))
        ctx.addLine(to: CGPoint(x: cx + bodyW * 0.12, y: bodyY + bodyH * 0.35))
        ctx.addLine(to: CGPoint(x: cx + bodyW * 0.08, y: bodyY - bodyH * 0.15))
        ctx.addLine(to: CGPoint(x: cx - bodyW * 0.08, y: bodyY - bodyH * 0.15))
        ctx.fillPath()

        // Left arm (cardigan)
        let lax = cx - (bodyW / 2 + s * 0.04)
        let lay = bodyY + bodyH * 0.05
        ctx.saveGState()
        ctx.translateBy(x: lax, y: lay)
        ctx.rotate(by: -0.3)
        outlinedEllipse(ctx, rect: CGRect(x: -s * 0.03, y: -s * 0.055, width: s * 0.06, height: s * 0.11), fill: cardigan, outline: ol)
        ctx.restoreGState()

        // Right arm angled to hold paintbrush
        let rax = cx + (bodyW / 2 + s * 0.02)
        let ray = bodyY + bodyH * 0.08
        ctx.saveGState()
        ctx.translateBy(x: rax, y: ray)
        ctx.rotate(by: 0.15)
        outlinedEllipse(ctx, rect: CGRect(x: -s * 0.03, y: -s * 0.055, width: s * 0.06, height: s * 0.11), fill: cardigan, outline: ol)
        ctx.restoreGState()

        // Paintbrush in right hand
        let brushX = cx + bodyW * 0.55
        let brushY = bodyY + bodyH * 0.15
        ctx.setStrokeColor(CGColor(red: 0.55, green: 0.40, blue: 0.20, alpha: 1))
        ctx.setLineWidth(s * 0.008)
        ctx.move(to: CGPoint(x: brushX, y: brushY - s * 0.04))
        ctx.addLine(to: CGPoint(x: brushX + s * 0.01, y: brushY + s * 0.05))
        ctx.strokePath()
        // Brush tip
        ctx.setFillColor(CGColor(red: 0.35, green: 0.55, blue: 0.78, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: brushX + s * 0.005 - s * 0.008,
                                   y: brushY + s * 0.045,
                                   width: s * 0.016, height: s * 0.022))
        // Ferrule (metal band)
        ctx.setFillColor(CGColor(gray: 0.70, alpha: 1))
        ctx.fill(CGRect(x: brushX - s * 0.005, y: brushY + s * 0.035, width: s * 0.014, height: s * 0.012))

        // Head
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: skin, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // Auburn curly hair — flowing waves framing face
        ctx.saveGState()
        ctx.addEllipse(in: headRect)
        ctx.clip()
        ctx.setFillColor(hairColor)
        ctx.fill(CGRect(x: cx - headR, y: headY + headR * 0.25, width: headR * 2, height: headR * 0.80))
        // Soft center part
        ctx.setFillColor(skin)
        ctx.fillEllipse(in: CGRect(x: cx - headR * 0.06, y: headY + headR * 0.55, width: headR * 0.12, height: headR * 0.30))
        ctx.restoreGState()
        // Curly wave highlights on each side
        ctx.setStrokeColor(hairHighlight)
        ctx.setLineWidth(s * 0.008)
        ctx.setLineCap(.round)
        for dir: CGFloat in [-1, 1] {
            let wx = cx + dir * headR * 0.55
            // Wave curl lines
            ctx.move(to: CGPoint(x: wx, y: headY + headR * 0.15))
            ctx.addQuadCurve(to: CGPoint(x: wx + dir * headR * 0.12, y: headY - headR * 0.20),
                             control: CGPoint(x: wx + dir * headR * 0.22, y: headY))
            ctx.move(to: CGPoint(x: wx + dir * headR * 0.05, y: headY - headR * 0.10))
            ctx.addQuadCurve(to: CGPoint(x: wx + dir * headR * 0.18, y: headY - headR * 0.45),
                             control: CGPoint(x: wx + dir * headR * 0.28, y: headY - headR * 0.25))
        }
        ctx.strokePath()
        ctx.setLineCap(.butt)

        // Soft warm eyes with slight lashes
        let eyeY = headY - headR * 0.05
        let sp = headR * 0.35
        let ew = headR * 0.24, eh = headR * 0.30
        for dir: CGFloat in [-1, 1] {
            let ex = cx + dir * sp
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex - ew - 1.5, y: eyeY - eh - 1.5, width: (ew + 1.5) * 2, height: (eh + 1.5) * 2))
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex - ew, y: eyeY - eh, width: ew * 2, height: eh * 2))
            // Green-hazel pupils
            let pw = ew * 0.52, ph = eh * 0.52
            ctx.setFillColor(CGColor(red: 0.35, green: 0.50, blue: 0.35, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex - pw, y: eyeY - ph, width: pw * 2, height: ph * 2))
            // Inner dark pupil
            let ip = pw * 0.5
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex - ip, y: eyeY - ip, width: ip * 2, height: ip * 2))
            let hlR = ew * 0.28
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex + ew * 0.2 - hlR / 2, y: eyeY + eh * 0.25 - hlR / 2, width: hlR, height: hlR))
            // Small lashes at corners
            ctx.setStrokeColor(CGColor(gray: 0.15, alpha: 1))
            ctx.setLineWidth(s * 0.006)
            ctx.move(to: CGPoint(x: ex + dir * ew * 0.85, y: eyeY + eh * 0.55))
            ctx.addLine(to: CGPoint(x: ex + dir * ew * 1.1, y: eyeY + eh * 0.75))
            ctx.strokePath()
        }

        // Gentle warm smile
        drawSmile(ctx, cx: cx, headY: headY, headR: headR, size: s)

        // Rosy cheeks
        ctx.setFillColor(CGColor(red: 0.90, green: 0.60, blue: 0.55, alpha: 0.28))
        for dir: CGFloat in [-1, 1] {
            let cheekX = cx + dir * headR * 0.45
            let cheekY = headY - headR * 0.22
            let cheekR = headR * 0.13
            ctx.fillEllipse(in: CGRect(x: cheekX - cheekR, y: cheekY - cheekR, width: cheekR * 2, height: cheekR * 2))
        }
    }

    // MARK: - Angela Martin

    private static func drawAngela(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2
        let headR = s * 0.28
        let headY = s * 0.60
        let bodyW = s * 0.24, bodyH = s * 0.20
        let bodyY = s * 0.25

        let skin = CGColor(red: 0.94, green: 0.85, blue: 0.78, alpha: 1)
        let outfit = CGColor(red: 0.85, green: 0.82, blue: 0.72, alpha: 1)
        let shoe = CGColor(red: 0.50, green: 0.42, blue: 0.35, alpha: 1)
        let blondeHair = CGColor(red: 0.88, green: 0.78, blue: 0.52, alpha: 1)

        // Tiny cat sitting next to Angela's feet
        let catX = cx - bodyW * 0.65
        let catY = bodyY - bodyH / 2 - s * 0.02
        let catR = s * 0.035
        // Cat body
        ctx.setFillColor(CGColor(gray: 0.85, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: catX - catR, y: catY - catR * 0.8, width: catR * 2, height: catR * 1.6))
        // Cat head
        let catHeadR = catR * 0.7
        ctx.fillEllipse(in: CGRect(x: catX - catHeadR, y: catY + catR * 0.6, width: catHeadR * 2, height: catHeadR * 2))
        // Cat ears (triangles)
        ctx.setFillColor(CGColor(gray: 0.85, alpha: 1))
        for dir: CGFloat in [-1, 1] {
            ctx.move(to: CGPoint(x: catX + dir * catHeadR * 0.5, y: catY + catR * 0.6 + catHeadR * 1.6))
            ctx.addLine(to: CGPoint(x: catX + dir * catHeadR * 0.9, y: catY + catR * 0.6 + catHeadR * 2.3))
            ctx.addLine(to: CGPoint(x: catX + dir * catHeadR * 0.1, y: catY + catR * 0.6 + catHeadR * 1.8))
            ctx.fillPath()
        }
        // Cat eyes — tiny dots
        ctx.setFillColor(CGColor(gray: 0.2, alpha: 1))
        for dir: CGFloat in [-1, 1] {
            ctx.fillEllipse(in: CGRect(x: catX + dir * catHeadR * 0.35 - catR * 0.08,
                                       y: catY + catR * 0.6 + catHeadR * 1.0,
                                       width: catR * 0.16, height: catR * 0.16))
        }
        // Cat tail curling up
        ctx.setStrokeColor(CGColor(gray: 0.80, alpha: 1))
        ctx.setLineWidth(s * 0.006)
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: catX + catR, y: catY))
        ctx.addQuadCurve(to: CGPoint(x: catX + catR * 1.5, y: catY + catR * 1.2),
                         control: CGPoint(x: catX + catR * 2.2, y: catY + catR * 0.3))
        ctx.strokePath()
        ctx.setLineCap(.butt)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW * 0.9, h: s * 0.035)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: shoe, size: s)

        // Body — conservative beige outfit
        let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH)
        outlinedEllipse(ctx, rect: bodyRect, fill: outfit, outline: ol)

        // Cross necklace
        ctx.setStrokeColor(CGColor(red: 0.75, green: 0.68, blue: 0.45, alpha: 1))
        ctx.setLineWidth(s * 0.008)
        let crossY = bodyY + bodyH * 0.25
        ctx.move(to: CGPoint(x: cx, y: crossY + s * 0.03))
        ctx.addLine(to: CGPoint(x: cx, y: crossY - s * 0.02))
        ctx.strokePath()
        ctx.move(to: CGPoint(x: cx - s * 0.012, y: crossY + s * 0.015))
        ctx.addLine(to: CGPoint(x: cx + s * 0.012, y: crossY + s * 0.015))
        ctx.strokePath()

        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: outfit, size: s)

        // Head
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: skin, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // Hair pulled back very tightly — smooth, flat to head
        ctx.saveGState()
        ctx.addEllipse(in: headRect)
        ctx.clip()
        ctx.setFillColor(blondeHair)
        ctx.fill(CGRect(x: cx - headR, y: headY + headR * 0.40, width: headR * 2, height: headR * 0.65))
        ctx.restoreGState()

        // Tight severe bun on back of head
        let bunR = headR * 0.22
        let bunY = headY + headR * 0.95
        outlinedEllipse(ctx, rect: CGRect(x: cx - bunR, y: bunY - bunR, width: bunR * 2, height: bunR * 2),
                        fill: blondeHair, outline: ol)
        // Hair pin
        ctx.setStrokeColor(CGColor(red: 0.70, green: 0.62, blue: 0.40, alpha: 1))
        ctx.setLineWidth(s * 0.005)
        ctx.move(to: CGPoint(x: cx - bunR * 0.3, y: bunY + bunR * 0.8))
        ctx.addLine(to: CGPoint(x: cx + bunR * 0.3, y: bunY + bunR * 1.2))
        ctx.strokePath()

        // Narrow disapproving eyes — half-lidded, icy
        let eyeY = headY - headR * 0.02
        let sp = headR * 0.32
        let ew = headR * 0.20, eh = headR * 0.20
        for dir: CGFloat in [-1, 1] {
            let ex = cx + dir * sp
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex - ew - 1.5, y: eyeY - eh - 1.5, width: (ew + 1.5) * 2, height: (eh + 1.5) * 2))
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex - ew, y: eyeY - eh, width: ew * 2, height: eh * 2))
            // Light blue-gray iris
            let pw = ew * 0.52, ph = eh * 0.52
            ctx.setFillColor(CGColor(red: 0.55, green: 0.62, blue: 0.70, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex - pw, y: eyeY - ph, width: pw * 2, height: ph * 2))
            let ip = pw * 0.5
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex - ip, y: eyeY - ip, width: ip * 2, height: ip * 2))
            let hlR = ew * 0.25
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex + ew * 0.2 - hlR / 2, y: eyeY + eh * 0.2 - hlR / 2, width: hlR, height: hlR))
            // Heavy disapproving upper lid
            ctx.setFillColor(skin)
            ctx.fillEllipse(in: CGRect(x: ex - ew * 1.1, y: eyeY + eh * 0.15, width: ew * 2.2, height: eh * 0.8))
        }

        // Disapproving thin eyebrows
        ctx.setStrokeColor(blondeHair)
        ctx.setLineWidth(s * 0.010)
        ctx.setLineCap(.round)
        for dir: CGFloat in [-1, 1] {
            let bx = cx + dir * headR * 0.32
            let by = headY + headR * 0.20
            ctx.move(to: CGPoint(x: bx - dir * headR * 0.12, y: by + headR * 0.02))
            ctx.addLine(to: CGPoint(x: bx + dir * headR * 0.12, y: by - headR * 0.01))
        }
        ctx.strokePath()
        ctx.setLineCap(.butt)

        // Pursed tight lips — tiny, disapproving
        ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
        ctx.setLineWidth(max(s * 0.013, 1.0))
        ctx.setLineCap(.round)
        let mouthY = headY - headR * 0.38
        ctx.move(to: CGPoint(x: cx - headR * 0.07, y: mouthY + headR * 0.01))
        ctx.addQuadCurve(to: CGPoint(x: cx + headR * 0.07, y: mouthY + headR * 0.01),
                         control: CGPoint(x: cx, y: mouthY - headR * 0.02))
        ctx.strokePath()
        ctx.setLineCap(.butt)
    }

    // MARK: - Kevin Malone

    private static func drawKevin(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2
        let headR = s * 0.34
        let headY = s * 0.61
        let bodyW = s * 0.32, bodyH = s * 0.24
        let bodyY = s * 0.25

        let skin = CGColor(red: 0.92, green: 0.80, blue: 0.70, alpha: 1)
        let greenCardigan = CGColor(red: 0.35, green: 0.52, blue: 0.35, alpha: 1)
        let shirt = CGColor(gray: 0.90, alpha: 1)
        let shoe = CGColor(gray: 0.18, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW * 1.1, h: s * 0.04)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: shoe, size: s)

        // Body — green cardigan, wider than others
        let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH)
        outlinedEllipse(ctx, rect: bodyRect, fill: greenCardigan, outline: ol)

        // Shirt underneath
        ctx.setFillColor(shirt)
        ctx.move(to: CGPoint(x: cx - bodyW * 0.15, y: bodyY + bodyH * 0.38))
        ctx.addLine(to: CGPoint(x: cx + bodyW * 0.15, y: bodyY + bodyH * 0.38))
        ctx.addLine(to: CGPoint(x: cx + bodyW * 0.10, y: bodyY - bodyH * 0.1))
        ctx.addLine(to: CGPoint(x: cx - bodyW * 0.10, y: bodyY - bodyH * 0.1))
        ctx.fillPath()

        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: greenCardigan, size: s)

        // Head — round and wide
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: skin, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // Bald — very short hair stubble on sides only
        ctx.setFillColor(CGColor(red: 0.40, green: 0.30, blue: 0.22, alpha: 0.25))
        ctx.saveGState()
        ctx.addEllipse(in: headRect)
        ctx.clip()
        ctx.fill(CGRect(x: cx - headR, y: headY - headR * 0.25, width: headR * 0.35, height: headR * 0.65))
        ctx.fill(CGRect(x: cx + headR * 0.65, y: headY - headR * 0.25, width: headR * 0.35, height: headR * 0.65))
        ctx.restoreGState()

        // Dopey half-closed eyes — droopy lids
        let eyeY = headY - headR * 0.02
        let sp = headR * 0.42
        let ew = headR * 0.15, eh = headR * 0.18
        for dir: CGFloat in [-1, 1] {
            let ex = cx + dir * sp
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex - ew - 1.5, y: eyeY - eh - 1.5, width: (ew + 1.5) * 2, height: (eh + 1.5) * 2))
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex - ew, y: eyeY - eh, width: ew * 2, height: eh * 2))
            let pw = ew * 0.60
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex - pw, y: eyeY - pw * 0.8, width: pw * 2, height: pw * 1.6))
            let hlR = ew * 0.28
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex + ew * 0.15 - hlR / 2, y: eyeY + eh * 0.15 - hlR / 2, width: hlR, height: hlR))
            // Heavy droopy upper eyelid
            ctx.setFillColor(skin)
            ctx.fillEllipse(in: CGRect(x: ex - ew * 1.2, y: eyeY + eh * 0.0, width: ew * 2.4, height: eh * 1.0))
        }

        // Simple short eyebrows
        ctx.setStrokeColor(CGColor(red: 0.35, green: 0.25, blue: 0.18, alpha: 0.6))
        ctx.setLineWidth(s * 0.012)
        ctx.setLineCap(.round)
        for dir: CGFloat in [-1, 1] {
            let bx = cx + dir * sp
            ctx.move(to: CGPoint(x: bx - headR * 0.10, y: eyeY + eh * 1.15))
            ctx.addLine(to: CGPoint(x: bx + headR * 0.10, y: eyeY + eh * 1.10))
        }
        ctx.strokePath()
        ctx.setLineCap(.butt)

        // Big wide dopey open-mouth grin
        let mouthY = headY - headR * 0.42
        let mouthW = headR * 0.42
        let mouthH = headR * 0.22
        ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: cx - mouthW, y: mouthY - mouthH, width: mouthW * 2, height: mouthH * 2))
        // Upper teeth row
        ctx.setFillColor(CGColor(gray: 0.95, alpha: 1))
        ctx.fill(CGRect(x: cx - mouthW * 0.78, y: mouthY, width: mouthW * 1.56, height: mouthH * 0.75))
        // Tongue hint at bottom
        ctx.setFillColor(CGColor(red: 0.85, green: 0.50, blue: 0.48, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: cx - mouthW * 0.35, y: mouthY - mouthH * 0.75, width: mouthW * 0.7, height: mouthH * 0.6))
    }

    // MARK: - Stanley Hudson

    private static func drawStanley(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2
        let headR = s * 0.32
        let headY = s * 0.62
        let bodyW = s * 0.30, bodyH = s * 0.22
        let bodyY = s * 0.25

        let skin = CGColor(red: 0.42, green: 0.30, blue: 0.22, alpha: 1)
        let sweaterVest = CGColor(red: 0.55, green: 0.45, blue: 0.32, alpha: 1)
        let whiteShirt = CGColor(gray: 0.92, alpha: 1)
        let shoe = CGColor(gray: 0.15, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW, h: s * 0.04)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: shoe, size: s)

        // Body — sweater vest over white shirt
        let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH)
        outlinedEllipse(ctx, rect: bodyRect, fill: sweaterVest, outline: ol)

        // White shirt collar — collared, wider showing
        ctx.setFillColor(whiteShirt)
        ctx.move(to: CGPoint(x: cx - bodyW * 0.22, y: bodyY + bodyH * 0.42))
        ctx.addLine(to: CGPoint(x: cx + bodyW * 0.22, y: bodyY + bodyH * 0.42))
        ctx.addLine(to: CGPoint(x: cx + bodyW * 0.14, y: bodyY + bodyH * 0.20))
        ctx.addLine(to: CGPoint(x: cx - bodyW * 0.14, y: bodyY + bodyH * 0.20))
        ctx.fillPath()

        // Left arm (white shirt sleeve)
        let lax = cx - (bodyW / 2 + s * 0.04)
        let lay = bodyY + bodyH * 0.05
        ctx.saveGState()
        ctx.translateBy(x: lax, y: lay)
        ctx.rotate(by: -0.3)
        outlinedEllipse(ctx, rect: CGRect(x: -s * 0.03, y: -s * 0.055, width: s * 0.06, height: s * 0.11), fill: whiteShirt, outline: ol)
        ctx.restoreGState()

        // Right arm holding crossword
        let rax = cx + (bodyW / 2 + s * 0.02)
        let ray = bodyY + bodyH * 0.10
        ctx.saveGState()
        ctx.translateBy(x: rax, y: ray)
        ctx.rotate(by: 0.1)
        outlinedEllipse(ctx, rect: CGRect(x: -s * 0.03, y: -s * 0.055, width: s * 0.06, height: s * 0.11), fill: whiteShirt, outline: ol)
        ctx.restoreGState()

        // Crossword puzzle paper
        let cwX = cx + bodyW * 0.52
        let cwY = bodyY + bodyH * 0.0
        let cwW = s * 0.07, cwH = s * 0.055
        // Paper
        outlinedRect(ctx, rect: CGRect(x: cwX - cwW / 2, y: cwY - cwH / 2, width: cwW, height: cwH),
                     fill: CGColor(gray: 0.96, alpha: 1), outline: ol * 0.5)
        // Grid lines
        ctx.setStrokeColor(CGColor(gray: 0.6, alpha: 1))
        ctx.setLineWidth(s * 0.003)
        let gridStep = cwW / 4
        for i in 1..<4 {
            let offset = CGFloat(i) * gridStep
            ctx.move(to: CGPoint(x: cwX - cwW / 2 + offset, y: cwY - cwH / 2))
            ctx.addLine(to: CGPoint(x: cwX - cwW / 2 + offset, y: cwY + cwH / 2))
            let oy = CGFloat(i) * cwH / 3
            ctx.move(to: CGPoint(x: cwX - cwW / 2, y: cwY - cwH / 2 + oy))
            ctx.addLine(to: CGPoint(x: cwX + cwW / 2, y: cwY - cwH / 2 + oy))
        }
        ctx.strokePath()
        // Black squares in crossword
        ctx.setFillColor(CGColor(gray: 0.15, alpha: 1))
        ctx.fill(CGRect(x: cwX - cwW / 2, y: cwY - cwH / 2, width: gridStep, height: cwH / 3))
        ctx.fill(CGRect(x: cwX + cwW / 2 - gridStep, y: cwY + cwH / 2 - cwH / 3, width: gridStep, height: cwH / 3))

        // Pencil
        ctx.setStrokeColor(CGColor(red: 0.85, green: 0.75, blue: 0.20, alpha: 1))
        ctx.setLineWidth(s * 0.006)
        ctx.move(to: CGPoint(x: cwX + cwW * 0.35, y: cwY - cwH * 0.45))
        ctx.addLine(to: CGPoint(x: cwX + cwW * 0.55, y: cwY + cwH * 0.35))
        ctx.strokePath()

        // Head
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: skin, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // Completely bald on top — gray stubble on sides
        ctx.setFillColor(CGColor(gray: 0.45, alpha: 0.25))
        ctx.saveGState()
        ctx.addEllipse(in: headRect)
        ctx.clip()
        ctx.fill(CGRect(x: cx - headR, y: headY - headR * 0.30, width: headR * 0.38, height: headR * 0.70))
        ctx.fill(CGRect(x: cx + headR * 0.62, y: headY - headR * 0.30, width: headR * 0.38, height: headR * 0.70))
        ctx.restoreGState()

        // Round reading glasses
        ctx.setStrokeColor(CGColor(gray: 0.15, alpha: 1))
        ctx.setLineWidth(s * 0.016)
        for dir: CGFloat in [-1, 1] {
            let gx = cx + dir * headR * 0.32
            let gy = headY + headR * 0.02
            let gr = headR * 0.23
            ctx.addEllipse(in: CGRect(x: gx - gr, y: gy - gr, width: gr * 2, height: gr * 2))
        }
        ctx.strokePath()
        // Bridge
        ctx.move(to: CGPoint(x: cx - headR * 0.09, y: headY + headR * 0.04))
        ctx.addLine(to: CGPoint(x: cx + headR * 0.09, y: headY + headR * 0.04))
        ctx.strokePath()
        // Temple arms
        for dir: CGFloat in [-1, 1] {
            ctx.move(to: CGPoint(x: cx + dir * (headR * 0.32 + headR * 0.23), y: headY + headR * 0.02))
            ctx.addLine(to: CGPoint(x: cx + dir * headR * 0.85, y: headY - headR * 0.05))
        }
        ctx.strokePath()

        // Half-lidded unamused eyes behind glasses
        let eyeY = headY + headR * 0.0
        let sp = headR * 0.32
        let ew = headR * 0.18, eh = headR * 0.22
        for dir: CGFloat in [-1, 1] {
            let ex = cx + dir * sp
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex - ew - 1, y: eyeY - eh - 1, width: (ew + 1) * 2, height: (eh + 1) * 2))
            ctx.setFillColor(CGColor(gray: 0.90, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex - ew, y: eyeY - eh, width: ew * 2, height: eh * 2))
            let pw = ew * 0.55, ph = eh * 0.55
            ctx.setFillColor(CGColor(red: 0.25, green: 0.18, blue: 0.12, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex - pw, y: eyeY - ph, width: pw * 2, height: ph * 2))
            let hlR = ew * 0.22
            ctx.setFillColor(CGColor(gray: 0.9, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex + ew * 0.15 - hlR / 2, y: eyeY + eh * 0.15 - hlR / 2, width: hlR, height: hlR))
            // Heavy drooping upper eyelid — "I don't care" look
            ctx.setFillColor(skin)
            ctx.fillEllipse(in: CGRect(x: ex - ew * 1.15, y: eyeY - eh * 0.05, width: ew * 2.3, height: eh * 1.2))
        }

        // Gray walrus mustache — thick and wide
        let mustY = headY - headR * 0.25
        ctx.setFillColor(CGColor(gray: 0.50, alpha: 1))
        // Thick mustache shape
        ctx.move(to: CGPoint(x: cx - headR * 0.35, y: mustY))
        ctx.addQuadCurve(to: CGPoint(x: cx, y: mustY + headR * 0.05),
                         control: CGPoint(x: cx - headR * 0.18, y: mustY + headR * 0.12))
        ctx.addQuadCurve(to: CGPoint(x: cx + headR * 0.35, y: mustY),
                         control: CGPoint(x: cx + headR * 0.18, y: mustY + headR * 0.12))
        ctx.addQuadCurve(to: CGPoint(x: cx, y: mustY - headR * 0.08),
                         control: CGPoint(x: cx + headR * 0.15, y: mustY - headR * 0.02))
        ctx.addQuadCurve(to: CGPoint(x: cx - headR * 0.35, y: mustY),
                         control: CGPoint(x: cx - headR * 0.15, y: mustY - headR * 0.02))
        ctx.fillPath()

        // Grumpy downturned mouth below mustache
        ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
        ctx.setLineWidth(max(s * 0.016, 1.2))
        ctx.setLineCap(.round)
        let mouthY = headY - headR * 0.48
        ctx.addArc(center: CGPoint(x: cx, y: mouthY - headR * 0.05),
                   radius: headR * 0.13,
                   startAngle: .pi * 0.2,
                   endAngle: .pi * 0.8,
                   clockwise: false)
        ctx.strokePath()
        ctx.setLineCap(.butt)
    }

    // MARK: - Creed Bratton

    private static func drawCreed(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2
        let headR = s * 0.30
        let headY = s * 0.60
        let bodyW = s * 0.26, bodyH = s * 0.20
        let bodyY = s * 0.25

        let skin = CGColor(red: 0.88, green: 0.78, blue: 0.70, alpha: 1)
        let shirt = CGColor(red: 0.60, green: 0.58, blue: 0.55, alpha: 1)
        let shoe = CGColor(gray: 0.20, alpha: 1)
        let whiteHair = CGColor(gray: 0.82, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW, h: s * 0.04)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: shoe, size: s)

        // Body — nondescript gray-green open-collar shirt
        let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH)
        outlinedEllipse(ctx, rect: bodyRect, fill: shirt, outline: ol)

        // Open collar showing skin — no tie
        ctx.setFillColor(skin)
        ctx.move(to: CGPoint(x: cx - bodyW * 0.08, y: bodyY + bodyH * 0.40))
        ctx.addLine(to: CGPoint(x: cx + bodyW * 0.08, y: bodyY + bodyH * 0.40))
        ctx.addLine(to: CGPoint(x: cx, y: bodyY + bodyH * 0.10))
        ctx.fillPath()

        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: shirt, size: s)

        // Head — slightly paler skin
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: skin, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // Bald top with sparse wispy white hair on sides
        ctx.saveGState()
        ctx.addEllipse(in: headRect)
        ctx.clip()
        ctx.setFillColor(whiteHair)
        // Very thin patches on sides — sparse, not solid
        ctx.fill(CGRect(x: cx - headR, y: headY - headR * 0.10, width: headR * 0.28, height: headR * 0.45))
        ctx.fill(CGRect(x: cx + headR * 0.72, y: headY - headR * 0.10, width: headR * 0.28, height: headR * 0.45))
        ctx.restoreGState()

        // Wispy tufts sticking out at odd angles
        ctx.setStrokeColor(whiteHair)
        ctx.setLineWidth(s * 0.007)
        ctx.setLineCap(.round)
        for dir: CGFloat in [-1, 1] {
            let baseX = cx + dir * headR * 0.85
            let baseY = headY + headR * 0.12
            // Multiple wispy strands
            ctx.move(to: CGPoint(x: baseX, y: baseY))
            ctx.addQuadCurve(to: CGPoint(x: baseX + dir * s * 0.04, y: baseY + s * 0.03),
                             control: CGPoint(x: baseX + dir * s * 0.02, y: baseY + s * 0.04))
            ctx.move(to: CGPoint(x: baseX, y: baseY - headR * 0.12))
            ctx.addLine(to: CGPoint(x: baseX + dir * s * 0.03, y: baseY - headR * 0.08))
            ctx.move(to: CGPoint(x: baseX - dir * headR * 0.05, y: baseY + headR * 0.10))
            ctx.addLine(to: CGPoint(x: baseX + dir * s * 0.025, y: baseY + headR * 0.15))
        }
        ctx.strokePath()
        ctx.setLineCap(.butt)

        // Wrinkle lines — forehead and around eyes
        ctx.setStrokeColor(CGColor(red: 0.72, green: 0.62, blue: 0.55, alpha: 0.4))
        ctx.setLineWidth(s * 0.005)
        // Forehead wrinkles
        ctx.move(to: CGPoint(x: cx - headR * 0.30, y: headY + headR * 0.30))
        ctx.addLine(to: CGPoint(x: cx + headR * 0.30, y: headY + headR * 0.32))
        ctx.move(to: CGPoint(x: cx - headR * 0.25, y: headY + headR * 0.22))
        ctx.addLine(to: CGPoint(x: cx + headR * 0.25, y: headY + headR * 0.23))
        ctx.strokePath()
        // Crow's feet
        for dir: CGFloat in [-1, 1] {
            let cfX = cx + dir * headR * 0.55
            let cfY = headY - headR * 0.05
            ctx.move(to: CGPoint(x: cfX, y: cfY + headR * 0.06))
            ctx.addLine(to: CGPoint(x: cfX + dir * headR * 0.10, y: cfY + headR * 0.10))
            ctx.move(to: CGPoint(x: cfX, y: cfY))
            ctx.addLine(to: CGPoint(x: cfX + dir * headR * 0.10, y: cfY))
            ctx.move(to: CGPoint(x: cfX, y: cfY - headR * 0.06))
            ctx.addLine(to: CGPoint(x: cfX + dir * headR * 0.10, y: cfY - headR * 0.08))
        }
        ctx.strokePath()

        // Wild unfocused eyes — pupils looking in different directions
        let eyeY = headY - headR * 0.05
        let sp = headR * 0.38
        let ew = headR * 0.24, eh = headR * 0.30
        for (i, dir): (Int, CGFloat) in [(-1 as CGFloat), (1 as CGFloat)].enumerated().map({ ($0.offset, $0.element) }) {
            let ex = cx + dir * sp
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex - ew - 1.5, y: eyeY - eh - 1.5, width: (ew + 1.5) * 2, height: (eh + 1.5) * 2))
            // Slightly yellowish sclera
            ctx.setFillColor(CGColor(red: 0.98, green: 0.96, blue: 0.90, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex - ew, y: eyeY - eh, width: ew * 2, height: eh * 2))
            // Pupils offset in opposite directions — unfocused
            let pw = ew * 0.48, ph = eh * 0.48
            let pupilOffsetX = (i == 0) ? -ew * 0.18 : ew * 0.20
            let pupilOffsetY = (i == 0) ? eh * 0.08 : -eh * 0.10
            // Lighter iris ring
            ctx.setFillColor(CGColor(red: 0.50, green: 0.55, blue: 0.55, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex + pupilOffsetX - pw * 1.3, y: eyeY + pupilOffsetY - ph * 1.3,
                                       width: pw * 2.6, height: ph * 2.6))
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex + pupilOffsetX - pw, y: eyeY + pupilOffsetY - ph, width: pw * 2, height: ph * 2))
            let hlR = ew * 0.25
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex + pupilOffsetX + ew * 0.18 - hlR / 2,
                                       y: eyeY + pupilOffsetY + eh * 0.22 - hlR / 2, width: hlR, height: hlR))
        }

        // Thin sparse eyebrows
        ctx.setStrokeColor(CGColor(gray: 0.72, alpha: 0.5))
        ctx.setLineWidth(s * 0.008)
        ctx.setLineCap(.round)
        for dir: CGFloat in [-1, 1] {
            let bx = cx + dir * sp
            ctx.move(to: CGPoint(x: bx - headR * 0.12, y: eyeY + eh + headR * 0.06))
            ctx.addLine(to: CGPoint(x: bx + headR * 0.10, y: eyeY + eh + headR * 0.08))
        }
        ctx.strokePath()
        ctx.setLineCap(.butt)

        // Mysterious asymmetric half-smile
        ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
        ctx.setLineWidth(max(s * 0.015, 1.2))
        ctx.setLineCap(.round)
        let mouthY = headY - headR * 0.42
        // Left side — slightly down
        ctx.move(to: CGPoint(x: cx - headR * 0.16, y: mouthY - headR * 0.03))
        ctx.addQuadCurve(to: CGPoint(x: cx - headR * 0.02, y: mouthY),
                         control: CGPoint(x: cx - headR * 0.08, y: mouthY - headR * 0.01))
        ctx.strokePath()
        // Right side — curves up knowingly
        ctx.move(to: CGPoint(x: cx - headR * 0.02, y: mouthY))
        ctx.addQuadCurve(to: CGPoint(x: cx + headR * 0.18, y: mouthY + headR * 0.07),
                         control: CGPoint(x: cx + headR * 0.10, y: mouthY + headR * 0.02))
        ctx.strokePath()
        ctx.setLineCap(.butt)
    }
}
