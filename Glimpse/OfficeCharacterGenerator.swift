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
        if roll < 9 { return Character(rawValue: 0)! }  // 90% star character
        return Character(rawValue: 1 + (roll - 9) % (Character.allCases.count - 1))!
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

        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: suit, size: s)

        // Head
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: skin, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // Hair — combed brown with side part
        ctx.saveGState()
        ctx.addEllipse(in: headRect)
        ctx.clip()
        ctx.setFillColor(hair)
        // Hair covers top portion of head
        ctx.fill(CGRect(x: cx - headR, y: headY + headR * 0.25, width: headR * 2, height: headR * 0.8))
        // Side part — lighter gap on left side
        ctx.setFillColor(CGColor(red: 0.40, green: 0.30, blue: 0.20, alpha: 1))
        ctx.fill(CGRect(x: cx - headR * 0.2, y: headY + headR * 0.55, width: headR * 0.06, height: headR * 0.35))
        ctx.restoreGState()

        // Slightly raised eyebrows
        ctx.setStrokeColor(CGColor(red: 0.30, green: 0.20, blue: 0.12, alpha: 0.8))
        ctx.setLineWidth(s * 0.014)
        ctx.setLineCap(.round)
        for dir: CGFloat in [-1, 1] {
            let bx = cx + dir * headR * 0.35
            let by = headY + headR * 0.22
            ctx.move(to: CGPoint(x: bx - headR * 0.12, y: by - headR * 0.02))
            ctx.addLine(to: CGPoint(x: bx + headR * 0.12, y: by + headR * 0.04))
        }
        ctx.strokePath()
        ctx.setLineCap(.butt)

        // Eyes
        drawSimpleEyes(ctx, cx: cx, headY: headY, headR: headR, size: s, spacing: 0.35)

        // Goofy wide grin showing teeth
        let mouthY = headY - headR * 0.42
        let mouthW = headR * 0.35
        let mouthH = headR * 0.15
        // Mouth opening
        ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: cx - mouthW, y: mouthY - mouthH, width: mouthW * 2, height: mouthH * 2))
        // Teeth — white rectangle in mouth
        ctx.setFillColor(CGColor(gray: 0.95, alpha: 1))
        ctx.fill(CGRect(x: cx - mouthW * 0.7, y: mouthY - mouthH * 0.3, width: mouthW * 1.4, height: mouthH * 1.0))
        // Tooth line
        ctx.setStrokeColor(CGColor(gray: 0.8, alpha: 1))
        ctx.setLineWidth(s * 0.005)
        ctx.move(to: CGPoint(x: cx, y: mouthY + mouthH * 0.6))
        ctx.addLine(to: CGPoint(x: cx, y: mouthY - mouthH * 0.3))
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

        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: suitBrown, size: s)

        // Head — slightly large forehead
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: skin, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // Bowl-cut hair — sits lower on head
        ctx.saveGState()
        ctx.addEllipse(in: headRect)
        ctx.clip()
        ctx.setFillColor(hair)
        // Flat bowl shape across top
        ctx.fill(CGRect(x: cx - headR, y: headY + headR * 0.15, width: headR * 2, height: headR * 0.9))
        // Rounded fringe bottom edge
        ctx.setFillColor(skin)
        ctx.fillEllipse(in: CGRect(x: cx - headR * 1.1, y: headY - headR * 0.05, width: headR * 2.2, height: headR * 0.5))
        ctx.restoreGState()

        // Thick rectangular glasses
        ctx.setStrokeColor(CGColor(gray: 0.15, alpha: 1))
        ctx.setLineWidth(s * 0.018)
        for dir: CGFloat in [-1, 1] {
            let gx = cx + dir * headR * 0.32
            let gy = headY - headR * 0.02
            let gw = headR * 0.28, gh = headR * 0.22
            let glassRect = CGRect(x: gx - gw, y: gy - gh, width: gw * 2, height: gh * 2)
            ctx.stroke(glassRect)
        }
        // Bridge
        ctx.setLineWidth(s * 0.014)
        ctx.move(to: CGPoint(x: cx - headR * 0.04, y: headY))
        ctx.addLine(to: CGPoint(x: cx + headR * 0.04, y: headY))
        ctx.strokePath()

        // Eyes behind glasses
        drawSimpleEyes(ctx, cx: cx, headY: headY, headR: headR, size: s, spacing: 0.32)

        // Stern/serious expression — flat line mouth
        ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
        ctx.setLineWidth(max(s * 0.016, 1.2))
        ctx.setLineCap(.round)
        let mouthY = headY - headR * 0.42
        ctx.move(to: CGPoint(x: cx - headR * 0.15, y: mouthY))
        ctx.addLine(to: CGPoint(x: cx + headR * 0.15, y: mouthY))
        ctx.strokePath()
        // Slight downturn at corners
        ctx.setLineWidth(max(s * 0.012, 1.0))
        ctx.move(to: CGPoint(x: cx - headR * 0.15, y: mouthY))
        ctx.addLine(to: CGPoint(x: cx - headR * 0.18, y: mouthY - headR * 0.04))
        ctx.move(to: CGPoint(x: cx + headR * 0.15, y: mouthY))
        ctx.addLine(to: CGPoint(x: cx + headR * 0.18, y: mouthY - headR * 0.04))
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

        // Body — white shirt
        let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH)
        outlinedEllipse(ctx, rect: bodyRect, fill: whiteShirt, outline: ol)

        // Open collar — small V showing skin
        ctx.setFillColor(skin)
        ctx.move(to: CGPoint(x: cx - bodyW * 0.1, y: bodyY + bodyH * 0.42))
        ctx.addLine(to: CGPoint(x: cx + bodyW * 0.1, y: bodyY + bodyH * 0.42))
        ctx.addLine(to: CGPoint(x: cx, y: bodyY + bodyH * 0.15))
        ctx.fillPath()

        // Loosened blue tie — slightly off-center and askew
        ctx.setFillColor(looseTie)
        let tieX = cx + s * 0.008  // slightly off center
        let tieW = s * 0.02
        ctx.move(to: CGPoint(x: tieX - tieW, y: bodyY + bodyH * 0.30))
        ctx.addLine(to: CGPoint(x: tieX + tieW, y: bodyY + bodyH * 0.28))
        ctx.addLine(to: CGPoint(x: tieX + tieW * 0.8, y: bodyY - bodyH * 0.05))
        ctx.addLine(to: CGPoint(x: tieX, y: bodyY - bodyH * 0.15))
        ctx.addLine(to: CGPoint(x: tieX - tieW * 0.6, y: bodyY - bodyH * 0.05))
        ctx.fillPath()

        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: whiteShirt, size: s)

        // Head
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: skin, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // Floppy messy side-swept hair
        ctx.saveGState()
        ctx.addEllipse(in: headRect)
        ctx.clip()
        ctx.setFillColor(hair)
        ctx.fill(CGRect(x: cx - headR, y: headY + headR * 0.20, width: headR * 2, height: headR * 0.85))
        ctx.restoreGState()
        // Messy fringe swooping to the right
        ctx.setFillColor(hair)
        ctx.move(to: CGPoint(x: cx - headR * 0.7, y: headY + headR * 0.45))
        ctx.addLine(to: CGPoint(x: cx + headR * 0.8, y: headY + headR * 0.30))
        ctx.addLine(to: CGPoint(x: cx + headR * 0.5, y: headY + headR * 0.65))
        ctx.addLine(to: CGPoint(x: cx - headR * 0.3, y: headY + headR * 0.70))
        ctx.fillPath()
        // Extra hair tuft
        ctx.setFillColor(hair)
        ctx.move(to: CGPoint(x: cx + headR * 0.3, y: headY + headR * 0.65))
        ctx.addLine(to: CGPoint(x: cx + headR * 0.9, y: headY + headR * 0.40))
        ctx.addLine(to: CGPoint(x: cx + headR * 0.6, y: headY + headR * 0.75))
        ctx.fillPath()

        // Eyes
        drawSimpleEyes(ctx, cx: cx, headY: headY, headR: headR, size: s, spacing: 0.35)

        // Smirk — one-sided smile
        ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
        ctx.setLineWidth(max(s * 0.016, 1.2))
        ctx.setLineCap(.round)
        let mouthY = headY - headR * 0.40
        // Left side flat
        ctx.move(to: CGPoint(x: cx - headR * 0.18, y: mouthY))
        ctx.addLine(to: CGPoint(x: cx, y: mouthY))
        ctx.strokePath()
        // Right side curves up — the smirk
        ctx.addArc(center: CGPoint(x: cx + headR * 0.08, y: mouthY + headR * 0.06),
                   radius: headR * 0.12,
                   startAngle: -.pi * 0.5,
                   endAngle: 0,
                   clockwise: false)
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

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW, h: s * 0.04)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: shoe, size: s)

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

        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: cardigan, size: s)

        // Head
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: skin, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // Auburn hair — pulled back with visible hair on top
        ctx.saveGState()
        ctx.addEllipse(in: headRect)
        ctx.clip()
        ctx.setFillColor(hairColor)
        ctx.fill(CGRect(x: cx - headR, y: headY + headR * 0.30, width: headR * 2, height: headR * 0.75))
        // Hair parted in middle
        ctx.setFillColor(skin)
        ctx.fillEllipse(in: CGRect(x: cx - headR * 0.05, y: headY + headR * 0.50, width: headR * 0.10, height: headR * 0.25))
        ctx.restoreGState()

        // Ponytail — small oval behind head on the right
        let ptX = cx + headR * 0.6
        let ptY = headY + headR * 0.2
        let ptW = headR * 0.25, ptH = headR * 0.40
        outlinedEllipse(ctx, rect: CGRect(x: ptX - ptW, y: ptY - ptH, width: ptW * 2, height: ptH * 2),
                        fill: hairColor, outline: ol)
        // Hair tie
        ctx.setFillColor(CGColor(red: 0.45, green: 0.25, blue: 0.15, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: ptX - headR * 0.08, y: ptY + ptH * 0.6, width: headR * 0.16, height: headR * 0.10))

        // Eyes
        drawSimpleEyes(ctx, cx: cx, headY: headY, headR: headR, size: s, spacing: 0.35)

        // Gentle warm smile
        drawSmile(ctx, cx: cx, headY: headY, headR: headR, size: s)

        // Rosy cheeks
        ctx.setFillColor(CGColor(red: 0.90, green: 0.60, blue: 0.55, alpha: 0.25))
        for dir: CGFloat in [-1, 1] {
            let cheekX = cx + dir * headR * 0.45
            let cheekY = headY - headR * 0.22
            let cheekR = headR * 0.12
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

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW * 0.9, h: s * 0.035)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: shoe, size: s)

        // Body — conservative beige outfit
        let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH)
        outlinedEllipse(ctx, rect: bodyRect, fill: outfit, outline: ol)

        // Cross necklace
        ctx.setStrokeColor(CGColor(red: 0.75, green: 0.68, blue: 0.45, alpha: 1))
        ctx.setLineWidth(s * 0.008)
        let crossY = bodyY + bodyH * 0.25
        // Vertical
        ctx.move(to: CGPoint(x: cx, y: crossY + s * 0.03))
        ctx.addLine(to: CGPoint(x: cx, y: crossY - s * 0.02))
        ctx.strokePath()
        // Horizontal
        ctx.move(to: CGPoint(x: cx - s * 0.012, y: crossY + s * 0.015))
        ctx.addLine(to: CGPoint(x: cx + s * 0.012, y: crossY + s * 0.015))
        ctx.strokePath()

        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: outfit, size: s)

        // Head
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: skin, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // Hair pulled back tightly
        ctx.saveGState()
        ctx.addEllipse(in: headRect)
        ctx.clip()
        ctx.setFillColor(blondeHair)
        ctx.fill(CGRect(x: cx - headR, y: headY + headR * 0.35, width: headR * 2, height: headR * 0.70))
        ctx.restoreGState()

        // Tight bun on top of head
        let bunR = headR * 0.25
        let bunY = headY + headR + bunR * 0.5
        outlinedEllipse(ctx, rect: CGRect(x: cx - bunR, y: bunY - bunR, width: bunR * 2, height: bunR * 2),
                        fill: blondeHair, outline: ol)

        // Narrow eyes — slightly smaller and closer together
        let eyeY = headY - headR * 0.02
        let sp = headR * 0.32
        let ew = headR * 0.20, eh = headR * 0.22
        for dir: CGFloat in [-1, 1] {
            let ex = cx + dir * sp
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex - ew - 1.5, y: eyeY - eh - 1.5, width: (ew + 1.5) * 2, height: (eh + 1.5) * 2))
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex - ew, y: eyeY - eh, width: ew * 2, height: eh * 2))
            let pw = ew * 0.55, ph = eh * 0.55
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex - pw, y: eyeY - ph, width: pw * 2, height: ph * 2))
            let hlR = ew * 0.28
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex + ew * 0.2 - hlR / 2, y: eyeY + eh * 0.25 - hlR / 2, width: hlR, height: hlR))
        }

        // Pursed disapproving lips — tiny tight mouth
        ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
        ctx.setLineWidth(max(s * 0.014, 1.0))
        ctx.setLineCap(.round)
        let mouthY = headY - headR * 0.38
        ctx.move(to: CGPoint(x: cx - headR * 0.08, y: mouthY))
        ctx.addLine(to: CGPoint(x: cx + headR * 0.08, y: mouthY))
        ctx.strokePath()
        ctx.setLineCap(.butt)
    }

    // MARK: - Kevin Malone

    private static func drawKevin(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2
        let headR = s * 0.34
        let headY = s * 0.61
        let bodyW = s * 0.30, bodyH = s * 0.24
        let bodyY = s * 0.25

        let skin = CGColor(red: 0.92, green: 0.80, blue: 0.70, alpha: 1)
        let greenCardigan = CGColor(red: 0.35, green: 0.52, blue: 0.35, alpha: 1)
        let shirt = CGColor(gray: 0.90, alpha: 1)
        let shoe = CGColor(gray: 0.18, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW * 1.1, h: s * 0.04)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: shoe, size: s)

        // Body — green cardigan, wide
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

        // Bald — very short hair, just a hint at the sides
        ctx.setFillColor(CGColor(red: 0.40, green: 0.30, blue: 0.22, alpha: 0.3))
        ctx.saveGState()
        ctx.addEllipse(in: headRect)
        ctx.clip()
        // Very faint stubble on sides
        ctx.fill(CGRect(x: cx - headR, y: headY - headR * 0.2, width: headR * 0.3, height: headR * 0.6))
        ctx.fill(CGRect(x: cx + headR * 0.7, y: headY - headR * 0.2, width: headR * 0.3, height: headR * 0.6))
        ctx.restoreGState()

        // Simple dot eyes set wide apart
        let eyeY = headY - headR * 0.02
        let sp = headR * 0.42
        let dotR = headR * 0.12
        for dir: CGFloat in [-1, 1] {
            let ex = cx + dir * sp
            // White sclera
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex - dotR - 1.5, y: eyeY - dotR - 1.5, width: (dotR + 1.5) * 2, height: (dotR + 1.5) * 2))
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex - dotR, y: eyeY - dotR, width: dotR * 2, height: dotR * 2))
            // Pupil
            let pw = dotR * 0.6
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex - pw, y: eyeY - pw, width: pw * 2, height: pw * 2))
            // Highlight
            let hlR = dotR * 0.3
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex + dotR * 0.2 - hlR / 2, y: eyeY + dotR * 0.25 - hlR / 2, width: hlR, height: hlR))
        }

        // Big wide silly grin
        let mouthY = headY - headR * 0.40
        let mouthW = headR * 0.40
        let mouthH = headR * 0.18
        ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: cx - mouthW, y: mouthY - mouthH, width: mouthW * 2, height: mouthH * 2))
        // Teeth
        ctx.setFillColor(CGColor(gray: 0.95, alpha: 1))
        ctx.fill(CGRect(x: cx - mouthW * 0.75, y: mouthY - mouthH * 0.2, width: mouthW * 1.5, height: mouthH * 1.1))
    }

    // MARK: - Stanley Hudson

    private static func drawStanley(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2
        let headR = s * 0.32
        let headY = s * 0.62
        let bodyW = s * 0.28, bodyH = s * 0.22
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

        // White shirt collar showing
        ctx.setFillColor(whiteShirt)
        ctx.move(to: CGPoint(x: cx - bodyW * 0.2, y: bodyY + bodyH * 0.42))
        ctx.addLine(to: CGPoint(x: cx + bodyW * 0.2, y: bodyY + bodyH * 0.42))
        ctx.addLine(to: CGPoint(x: cx + bodyW * 0.12, y: bodyY + bodyH * 0.25))
        ctx.addLine(to: CGPoint(x: cx - bodyW * 0.12, y: bodyY + bodyH * 0.25))
        ctx.fillPath()

        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: whiteShirt, size: s)

        // Head
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: skin, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // Bald on top — no hair drawn on top, just skin

        // Glasses
        ctx.setStrokeColor(CGColor(gray: 0.15, alpha: 1))
        ctx.setLineWidth(s * 0.015)
        for dir: CGFloat in [-1, 1] {
            let gx = cx + dir * headR * 0.32
            let gy = headY + headR * 0.02
            let gr = headR * 0.22
            ctx.addEllipse(in: CGRect(x: gx - gr, y: gy - gr, width: gr * 2, height: gr * 2))
        }
        ctx.strokePath()
        // Bridge
        ctx.move(to: CGPoint(x: cx - headR * 0.10, y: headY + headR * 0.02))
        ctx.addLine(to: CGPoint(x: cx + headR * 0.10, y: headY + headR * 0.02))
        ctx.strokePath()

        // Eyes behind glasses
        drawSimpleEyes(ctx, cx: cx, headY: headY, headR: headR, size: s, spacing: 0.32)

        // Gray mustache
        ctx.setFillColor(CGColor(gray: 0.55, alpha: 1))
        let mustW = headR * 0.30
        let mustH = headR * 0.10
        let mustY = headY - headR * 0.28
        ctx.fillEllipse(in: CGRect(x: cx - mustW, y: mustY - mustH, width: mustW * 2, height: mustH * 2))
        // Skin-colored cut to shape mustache (hide bottom half)
        ctx.setFillColor(skin)
        ctx.fillEllipse(in: CGRect(x: cx - mustW * 0.8, y: mustY - mustH * 2.2, width: mustW * 1.6, height: mustH * 2.0))

        // Grumpy downturned mouth
        ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
        ctx.setLineWidth(max(s * 0.016, 1.2))
        ctx.setLineCap(.round)
        let mouthY = headY - headR * 0.45
        ctx.addArc(center: CGPoint(x: cx, y: mouthY - headR * 0.05),
                   radius: headR * 0.15,
                   startAngle: .pi * 0.15,
                   endAngle: .pi * 0.85,
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

        let skin = CGColor(red: 0.90, green: 0.80, blue: 0.72, alpha: 1)
        let shirt = CGColor(red: 0.60, green: 0.58, blue: 0.55, alpha: 1)
        let shoe = CGColor(gray: 0.20, alpha: 1)
        let whiteHair = CGColor(gray: 0.82, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW, h: s * 0.04)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: shoe, size: s)

        // Body — nondescript shirt
        let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH)
        outlinedEllipse(ctx, rect: bodyRect, fill: shirt, outline: ol)

        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: shirt, size: s)

        // Head
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: skin, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // Bald with wispy white hair on sides
        ctx.saveGState()
        ctx.addEllipse(in: headRect)
        ctx.clip()
        ctx.setFillColor(whiteHair)
        // Wispy patches on left side
        ctx.fill(CGRect(x: cx - headR, y: headY - headR * 0.15, width: headR * 0.35, height: headR * 0.55))
        // Wispy patches on right side
        ctx.fill(CGRect(x: cx + headR * 0.65, y: headY - headR * 0.15, width: headR * 0.35, height: headR * 0.55))
        ctx.restoreGState()

        // Wispy tufts sticking out
        ctx.setStrokeColor(whiteHair)
        ctx.setLineWidth(s * 0.008)
        ctx.setLineCap(.round)
        for dir: CGFloat in [-1, 1] {
            let baseX = cx + dir * headR * 0.85
            let baseY = headY + headR * 0.15
            ctx.move(to: CGPoint(x: baseX, y: baseY))
            ctx.addLine(to: CGPoint(x: baseX + dir * s * 0.03, y: baseY + s * 0.025))
            ctx.move(to: CGPoint(x: baseX, y: baseY - headR * 0.15))
            ctx.addLine(to: CGPoint(x: baseX + dir * s * 0.025, y: baseY - headR * 0.15 + s * 0.02))
        }
        ctx.strokePath()
        ctx.setLineCap(.butt)

        // Slightly wild/unfocused eyes — offset pupils
        let eyeY = headY - headR * 0.05
        let sp = headR * 0.38
        let ew = headR * 0.24, eh = headR * 0.30
        for (i, dir): (Int, CGFloat) in [(-1 as CGFloat), (1 as CGFloat)].enumerated().map({ ($0.offset, $0.element) }) {
            let ex = cx + dir * sp
            // Dark socket
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex - ew - 1.5, y: eyeY - eh - 1.5, width: (ew + 1.5) * 2, height: (eh + 1.5) * 2))
            // White sclera
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex - ew, y: eyeY - eh, width: ew * 2, height: eh * 2))
            // Pupils — slightly offset in different directions for unfocused look
            let pw = ew * 0.50, ph = eh * 0.50
            let pupilOffsetX = (i == 0) ? -ew * 0.12 : ew * 0.15
            let pupilOffsetY = (i == 0) ? eh * 0.05 : -eh * 0.08
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex + pupilOffsetX - pw, y: eyeY + pupilOffsetY - ph, width: pw * 2, height: ph * 2))
            // Highlight
            let hlR = ew * 0.28
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex + pupilOffsetX + ew * 0.2 - hlR / 2, y: eyeY + pupilOffsetY + eh * 0.25 - hlR / 2, width: hlR, height: hlR))
        }

        // Mysterious half-smile — asymmetric
        ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
        ctx.setLineWidth(max(s * 0.015, 1.2))
        ctx.setLineCap(.round)
        let mouthY = headY - headR * 0.40
        // Left side slightly down
        ctx.move(to: CGPoint(x: cx - headR * 0.15, y: mouthY - headR * 0.02))
        ctx.addLine(to: CGPoint(x: cx - headR * 0.02, y: mouthY))
        ctx.strokePath()
        // Right side curves up
        ctx.move(to: CGPoint(x: cx - headR * 0.02, y: mouthY))
        ctx.addLine(to: CGPoint(x: cx + headR * 0.15, y: mouthY + headR * 0.05))
        ctx.strokePath()
        ctx.setLineCap(.butt)
    }
}
