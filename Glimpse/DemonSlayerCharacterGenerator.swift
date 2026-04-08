// Glimpse/DemonSlayerCharacterGenerator.swift
import AppKit

/// Generates chibi Demon Slayer characters procedurally using Core Graphics.
/// Same architecture as CharacterGenerator — deterministic mapping from sessionID.
enum DemonSlayerCharacterGenerator {

    // MARK: - Character Definitions

    enum Character: Int, CaseIterable {
        case tanjiro = 0
        case nezuko
        case zenitsu
        case inosuke
        case giyu
        case shinobu
        case rengoku
        case muzan
    }

    static func color(for sessionID: String) -> NSColor {
        let ch = character(for: sessionID)
        switch ch {
        case .tanjiro:  return NSColor(red: 0.30, green: 0.55, blue: 0.45, alpha: 1)  // green checkered
        case .nezuko:   return NSColor(red: 0.90, green: 0.50, blue: 0.60, alpha: 1)  // pink kimono
        case .zenitsu:  return NSColor(red: 0.95, green: 0.80, blue: 0.25, alpha: 1)  // yellow
        case .inosuke:  return NSColor(red: 0.40, green: 0.50, blue: 0.65, alpha: 1)  // blue/gray
        case .giyu:     return NSColor(red: 0.35, green: 0.30, blue: 0.55, alpha: 1)  // deep purple/blue
        case .shinobu:  return NSColor(red: 0.65, green: 0.45, blue: 0.75, alpha: 1)  // purple butterfly
        case .rengoku:  return NSColor(red: 0.92, green: 0.55, blue: 0.15, alpha: 1)  // flame orange
        case .muzan:    return NSColor(red: 0.20, green: 0.15, blue: 0.25, alpha: 1)  // dark
        }
    }

    // MARK: - Cache & RNG

    private class CGImageBox {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    private static let cache = NSCache<NSString, CGImageBox>()

    private static func seed(from sessionID: String) -> UInt64 {
        var hash: UInt64 = 5381
        for byte in sessionID.utf8 { hash = hash &* 33 &+ UInt64(byte) }
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
        if let cached = cache.object(forKey: cacheKey) { return cached.image }

        let scale: CGFloat = 2.0
        guard let ctx = CGContext(
            data: nil, width: Int(size * scale), height: Int(size * scale),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: 0, y: -size * 0.1)

        switch ch {
        case .tanjiro:  drawTanjiro(ctx, size: size)
        case .nezuko:   drawNezuko(ctx, size: size)
        case .zenitsu:  drawZenitsu(ctx, size: size)
        case .inosuke:  drawInosuke(ctx, size: size)
        case .giyu:     drawGiyu(ctx, size: size)
        case .shinobu:  drawShinobu(ctx, size: size)
        case .rengoku:  drawRengoku(ctx, size: size)
        case .muzan:    drawMuzan(ctx, size: size)
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

    private static func headHighlight(_ ctx: CGContext, headRect: CGRect, cx: CGFloat, headY: CGFloat, headR: CGFloat) {
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [CGColor(gray: 1, alpha: 0.18), CGColor(gray: 1, alpha: 0.03), CGColor(gray: 0, alpha: 0.06)] as CFArray,
            locations: [0, 0.5, 1]
        ) else { return }
        ctx.saveGState()
        ctx.addEllipse(in: headRect)
        ctx.clip()
        ctx.drawRadialGradient(gradient,
            startCenter: CGPoint(x: cx - headR * 0.25, y: headY + headR * 0.25), startRadius: 0,
            endCenter: CGPoint(x: cx, y: headY), endRadius: headR, options: [])
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

    private static func drawAnimeEyes(_ ctx: CGContext, cx: CGFloat, headY: CGFloat, headR: CGFloat, size s: CGFloat,
                                       irisColor: CGColor, spacing: CGFloat = 0.4) {
        let eyeY = headY - headR * 0.05
        let sp = headR * spacing
        let ew = headR * 0.26, eh = headR * 0.35

        for dir: CGFloat in [-1, 1] {
            let ex = cx + dir * sp
            // Dark socket
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex - ew - 1.5, y: eyeY - eh - 1.5, width: (ew + 1.5) * 2, height: (eh + 1.5) * 2))
            // White sclera
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex - ew, y: eyeY - eh, width: ew * 2, height: eh * 2))
            // Colored iris
            let iw = ew * 0.8, ih = eh * 0.8
            ctx.setFillColor(irisColor)
            ctx.fillEllipse(in: CGRect(x: ex - iw, y: eyeY - ih - eh * 0.05, width: iw * 2, height: ih * 2))
            // Dark pupil
            let pw = ew * 0.4, ph = eh * 0.45
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex - pw, y: eyeY - ph - eh * 0.1, width: pw * 2, height: ph * 2))
            // Big highlight
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            let hlR = ew * 0.32
            ctx.fillEllipse(in: CGRect(x: ex + ew * 0.15 - hlR / 2, y: eyeY + eh * 0.15 - hlR / 2, width: hlR, height: hlR))
            // Small highlight
            let shlR = ew * 0.15
            ctx.fillEllipse(in: CGRect(x: ex - ew * 0.25, y: eyeY - eh * 0.15, width: shlR, height: shlR))
        }
    }

    private static func drawSmile(_ ctx: CGContext, cx: CGFloat, headY: CGFloat, headR: CGFloat, size s: CGFloat) {
        ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
        ctx.setLineWidth(max(s * 0.018, 1.2))
        ctx.setLineCap(.round)
        ctx.addArc(center: CGPoint(x: cx, y: headY - headR * 0.3),
                   radius: headR * 0.15, startAngle: -.pi * 0.15, endAngle: -.pi * 0.85, clockwise: true)
        ctx.strokePath()
        ctx.setLineCap(.butt)
    }

    /// Draw spiky anime hair tufts on top of head.
    private static func drawSpikyHair(_ ctx: CGContext, cx: CGFloat, headY: CGFloat, headR: CGFloat, hairColor: CGColor,
                                       spikes: Int = 5, spikeH: CGFloat = 0.18, spread: CGFloat = 0.7, size s: CGFloat) {
        ctx.setFillColor(hairColor)
        let baseY = headY + headR * 0.6
        for i in 0..<spikes {
            let t = CGFloat(i) / CGFloat(spikes - 1) - 0.5  // -0.5 to 0.5
            let tipX = cx + t * headR * spread * 2.2
            let tipY = baseY + s * spikeH + abs(t) * s * 0.04  // outer spikes slightly taller
            let baseL = tipX - headR * 0.15
            let baseR = tipX + headR * 0.15
            ctx.move(to: CGPoint(x: baseL, y: baseY))
            ctx.addLine(to: CGPoint(x: tipX, y: tipY))
            ctx.addLine(to: CGPoint(x: baseR, y: baseY))
            ctx.fillPath()
        }
    }

    /// Draw a checkered pattern on a rectangular region (Tanjiro's haori).
    private static func drawCheckered(_ ctx: CGContext, rect: CGRect, color1: CGColor, color2: CGColor, gridSize: CGFloat) {
        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.setFillColor(color1)
        ctx.fill(rect)
        ctx.setFillColor(color2)
        let cols = Int(ceil(rect.width / gridSize))
        let rows = Int(ceil(rect.height / gridSize))
        for r in 0...rows {
            for c in 0...cols where (r + c) % 2 == 0 {
                ctx.fill(CGRect(x: rect.minX + CGFloat(c) * gridSize,
                                y: rect.minY + CGFloat(r) * gridSize,
                                width: gridSize, height: gridSize))
            }
        }
        ctx.restoreGState()
    }

    // MARK: - Tanjiro

    private static func drawTanjiro(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2
        let headR = s * 0.32, headY = s * 0.62
        let bodyW = s * 0.28, bodyH = s * 0.22, bodyY = s * 0.25

        let skin = CGColor(red: 0.92, green: 0.80, blue: 0.68, alpha: 1)
        let darkRed = CGColor(red: 0.55, green: 0.12, blue: 0.10, alpha: 1)
        let greenDark = CGColor(red: 0.20, green: 0.38, blue: 0.30, alpha: 1)
        let greenLight = CGColor(red: 0.15, green: 0.30, blue: 0.22, alpha: 1)
        let black = CGColor(gray: 0.12, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW, h: s * 0.04)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: black, size: s)

        // Body — green checkered haori
        let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH)
        outlinedEllipse(ctx, rect: bodyRect, fill: greenDark, outline: ol)

        // Checkered pattern on body (clipped to ellipse)
        ctx.saveGState()
        ctx.addEllipse(in: bodyRect)
        ctx.clip()
        drawCheckered(ctx, rect: bodyRect, color1: greenDark, color2: greenLight, gridSize: s * 0.04)
        ctx.restoreGState()

        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: greenDark, size: s)

        // Head
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: skin, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // Dark reddish-brown spiky hair
        drawSpikyHair(ctx, cx: cx, headY: headY, headR: headR, hairColor: darkRed, spikes: 7, spikeH: 0.15, size: s)

        // Hair cap — dark area on top of head
        ctx.saveGState()
        ctx.addEllipse(in: headRect)
        ctx.clip()
        ctx.setFillColor(darkRed)
        ctx.fill(CGRect(x: cx - headR, y: headY + headR * 0.15, width: headR * 2, height: headR))
        ctx.restoreGState()

        // Scar on forehead — distinctive mark
        ctx.setStrokeColor(CGColor(red: 0.75, green: 0.25, blue: 0.20, alpha: 0.9))
        ctx.setLineWidth(s * 0.015)
        ctx.setLineCap(.round)
        let scarX = cx - headR * 0.15
        let scarY = headY + headR * 0.35
        ctx.move(to: CGPoint(x: scarX - headR * 0.12, y: scarY + headR * 0.08))
        ctx.addLine(to: CGPoint(x: scarX + headR * 0.12, y: scarY - headR * 0.08))
        ctx.strokePath()
        // Scar flame shape
        ctx.setFillColor(CGColor(red: 0.75, green: 0.25, blue: 0.20, alpha: 0.7))
        ctx.fillEllipse(in: CGRect(x: scarX - headR * 0.06, y: scarY - headR * 0.06, width: headR * 0.12, height: headR * 0.12))
        ctx.setLineCap(.butt)

        // Hanafuda earrings — small rectangles hanging from ears
        for dir: CGFloat in [-1, 1] {
            let earX = cx + dir * headR * 0.85
            let earY = headY - headR * 0.1
            // Earring rectangle
            let erW = s * 0.02, erH = s * 0.04
            outlinedRect(ctx, rect: CGRect(x: earX - erW / 2, y: earY - erH, width: erW, height: erH),
                         fill: CGColor(gray: 0.95, alpha: 1), outline: ol * 0.3)
            // Red sun on earring
            ctx.setFillColor(CGColor(red: 0.85, green: 0.20, blue: 0.15, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: earX - s * 0.005, y: earY - erH * 0.6, width: s * 0.01, height: s * 0.01))
        }

        // Eyes — dark red/burgundy iris
        drawAnimeEyes(ctx, cx: cx, headY: headY, headR: headR, size: s,
                      irisColor: CGColor(red: 0.55, green: 0.18, blue: 0.18, alpha: 1))
        drawSmile(ctx, cx: cx, headY: headY, headR: headR, size: s)
    }

    // MARK: - Nezuko

    private static func drawNezuko(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2
        let headR = s * 0.32, headY = s * 0.62
        let bodyW = s * 0.26, bodyH = s * 0.20, bodyY = s * 0.25

        let skin = CGColor(red: 0.92, green: 0.80, blue: 0.70, alpha: 1)
        let pink = CGColor(red: 0.90, green: 0.50, blue: 0.58, alpha: 1)
        let darkPink = CGColor(red: 0.70, green: 0.35, blue: 0.40, alpha: 1)
        let hairBlack = CGColor(gray: 0.12, alpha: 1)
        let hairOrange = CGColor(red: 0.85, green: 0.45, blue: 0.25, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW, h: s * 0.04)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: pink, size: s)

        // Body — pink kimono
        let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH)
        outlinedEllipse(ctx, rect: bodyRect, fill: pink, outline: ol)

        // Kimono pattern — small triangles (asanoha-inspired)
        ctx.setStrokeColor(darkPink)
        ctx.setLineWidth(s * 0.005)
        ctx.saveGState()
        ctx.addEllipse(in: bodyRect)
        ctx.clip()
        let patternSize = s * 0.035
        for row in 0..<4 {
            for col in 0..<6 {
                let px = bodyRect.minX + CGFloat(col) * patternSize
                let py = bodyRect.minY + CGFloat(row) * patternSize
                ctx.move(to: CGPoint(x: px + patternSize / 2, y: py + patternSize))
                ctx.addLine(to: CGPoint(x: px, y: py))
                ctx.addLine(to: CGPoint(x: px + patternSize, y: py))
            }
        }
        ctx.strokePath()
        ctx.restoreGState()

        // Obi (belt)
        let obiH = bodyH * 0.18
        outlinedRect(ctx, rect: CGRect(x: cx - bodyW * 0.4, y: bodyY - obiH / 2, width: bodyW * 0.8, height: obiH),
                     fill: CGColor(red: 0.85, green: 0.35, blue: 0.40, alpha: 1), outline: ol * 0.5)

        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: pink, size: s)

        // Head
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: skin, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // Black hair with orange tips
        ctx.saveGState()
        ctx.addEllipse(in: headRect)
        ctx.clip()
        ctx.setFillColor(hairBlack)
        ctx.fill(CGRect(x: cx - headR, y: headY + headR * 0.1, width: headR * 2, height: headR))
        // Orange gradient at tips (side hair)
        ctx.setFillColor(hairOrange)
        ctx.fill(CGRect(x: cx - headR, y: headY + headR * 0.1, width: headR * 0.35, height: headR * 0.5))
        ctx.fill(CGRect(x: cx + headR * 0.65, y: headY + headR * 0.1, width: headR * 0.35, height: headR * 0.5))
        ctx.restoreGState()

        // Side hair strands hanging down
        for dir: CGFloat in [-1, 1] {
            let hx = cx + dir * headR * 0.8
            ctx.setFillColor(hairBlack)
            ctx.fillEllipse(in: CGRect(x: hx - s * 0.025, y: headY - headR * 0.4, width: s * 0.05, height: headR * 0.8))
            // Orange tips on strands
            ctx.setFillColor(hairOrange)
            ctx.fillEllipse(in: CGRect(x: hx - s * 0.022, y: headY - headR * 0.4, width: s * 0.044, height: headR * 0.3))
        }

        // Hair ribbon — pink
        ctx.setFillColor(pink)
        ctx.fillEllipse(in: CGRect(x: cx + headR * 0.2, y: headY + headR * 0.7, width: headR * 0.2, height: headR * 0.2))

        // Bamboo muzzle — distinctive feature
        let muzzleY = headY - headR * 0.3
        let muzzleW = headR * 0.5, muzzleH = headR * 0.15
        // Bamboo tube
        ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
        ctx.fill(CGRect(x: cx - muzzleW - ol, y: muzzleY - muzzleH / 2 - ol, width: muzzleW * 2 + ol * 2, height: muzzleH + ol * 2))
        ctx.setFillColor(CGColor(red: 0.55, green: 0.75, blue: 0.45, alpha: 1))
        ctx.fill(CGRect(x: cx - muzzleW, y: muzzleY - muzzleH / 2, width: muzzleW * 2, height: muzzleH))
        // Bamboo ring
        ctx.setStrokeColor(CGColor(red: 0.40, green: 0.58, blue: 0.32, alpha: 1))
        ctx.setLineWidth(s * 0.008)
        ctx.move(to: CGPoint(x: cx, y: muzzleY - muzzleH / 2))
        ctx.addLine(to: CGPoint(x: cx, y: muzzleY + muzzleH / 2))
        ctx.strokePath()

        // Eyes — pink iris (Nezuko's demon eyes)
        drawAnimeEyes(ctx, cx: cx, headY: headY, headR: headR, size: s,
                      irisColor: CGColor(red: 0.90, green: 0.40, blue: 0.55, alpha: 1))
    }

    // MARK: - Zenitsu

    private static func drawZenitsu(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2
        let headR = s * 0.32, headY = s * 0.62
        let bodyW = s * 0.28, bodyH = s * 0.22, bodyY = s * 0.25

        let skin = CGColor(red: 0.92, green: 0.82, blue: 0.70, alpha: 1)
        let yellow = CGColor(red: 0.95, green: 0.82, blue: 0.25, alpha: 1)
        let yellowDark = CGColor(red: 0.80, green: 0.65, blue: 0.15, alpha: 1)
        let orange = CGColor(red: 0.90, green: 0.60, blue: 0.20, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW, h: s * 0.04)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: yellowDark, size: s)

        // Body — yellow/orange gradient haori
        let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH)
        outlinedEllipse(ctx, rect: bodyRect, fill: yellow, outline: ol)

        // Triangle pattern (lightning-like) on haori
        ctx.saveGState()
        ctx.addEllipse(in: bodyRect)
        ctx.clip()
        ctx.setFillColor(orange)
        let triH = bodyH * 0.3
        for i in 0..<4 {
            let tx = bodyRect.minX + CGFloat(i) * bodyW * 0.3
            ctx.move(to: CGPoint(x: tx, y: bodyY - bodyH / 2))
            ctx.addLine(to: CGPoint(x: tx + bodyW * 0.15, y: bodyY - bodyH / 2 + triH))
            ctx.addLine(to: CGPoint(x: tx + bodyW * 0.3, y: bodyY - bodyH / 2))
            ctx.fillPath()
        }
        ctx.restoreGState()

        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: yellow, size: s)

        // Head
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: skin, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // Wild yellow spiky hair
        drawSpikyHair(ctx, cx: cx, headY: headY, headR: headR, hairColor: yellow, spikes: 9, spikeH: 0.20, spread: 0.8, size: s)

        // Hair cap
        ctx.saveGState()
        ctx.addEllipse(in: headRect)
        ctx.clip()
        ctx.setFillColor(yellow)
        ctx.fill(CGRect(x: cx - headR, y: headY + headR * 0.05, width: headR * 2, height: headR))
        // Orange roots
        ctx.setFillColor(orange)
        ctx.fill(CGRect(x: cx - headR * 0.6, y: headY + headR * 0.6, width: headR * 1.2, height: headR * 0.35))
        ctx.restoreGState()

        // Eyes — amber/golden, with scared/crying expression (teardrop)
        drawAnimeEyes(ctx, cx: cx, headY: headY, headR: headR, size: s,
                      irisColor: CGColor(red: 0.85, green: 0.65, blue: 0.20, alpha: 1))

        // Teardrop on one side (Zenitsu is always crying)
        ctx.setFillColor(CGColor(red: 0.55, green: 0.75, blue: 0.95, alpha: 0.7))
        let tearX = cx + headR * 0.55
        let tearY = headY - headR * 0.25
        ctx.fillEllipse(in: CGRect(x: tearX - s * 0.01, y: tearY - s * 0.025, width: s * 0.02, height: s * 0.04))

        // Worried mouth — wavy line
        ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
        ctx.setLineWidth(max(s * 0.015, 1))
        ctx.setLineCap(.round)
        let mouthY = headY - headR * 0.38
        ctx.move(to: CGPoint(x: cx - headR * 0.15, y: mouthY))
        ctx.addQuadCurve(to: CGPoint(x: cx, y: mouthY - headR * 0.06),
                         control: CGPoint(x: cx - headR * 0.08, y: mouthY - headR * 0.08))
        ctx.addQuadCurve(to: CGPoint(x: cx + headR * 0.15, y: mouthY),
                         control: CGPoint(x: cx + headR * 0.08, y: mouthY + headR * 0.02))
        ctx.strokePath()
        ctx.setLineCap(.butt)
    }

    // MARK: - Inosuke

    private static func drawInosuke(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2
        let headR = s * 0.34, headY = s * 0.62
        let bodyW = s * 0.30, bodyH = s * 0.22, bodyY = s * 0.25

        let skin = CGColor(red: 0.90, green: 0.78, blue: 0.65, alpha: 1)
        let boarGray = CGColor(red: 0.50, green: 0.48, blue: 0.45, alpha: 1)
        let boarDark = CGColor(red: 0.35, green: 0.32, blue: 0.28, alpha: 1)
        let blue = CGColor(red: 0.35, green: 0.45, blue: 0.65, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW, h: s * 0.04)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: skin, size: s)

        // Body — bare chest with fur trim
        let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH)
        outlinedEllipse(ctx, rect: bodyRect, fill: skin, outline: ol)

        // Blue fur shorts/loincloth
        ctx.saveGState()
        ctx.addEllipse(in: bodyRect)
        ctx.clip()
        ctx.setFillColor(blue)
        ctx.fill(CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH * 0.5))
        ctx.restoreGState()

        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: skin, size: s)

        // Boar mask — head (covers most of the face)
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: boarGray, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // Darker patches on mask
        ctx.saveGState()
        ctx.addEllipse(in: headRect)
        ctx.clip()
        ctx.setFillColor(boarDark)
        ctx.fillEllipse(in: CGRect(x: cx - headR * 0.6, y: headY + headR * 0.2, width: headR * 0.5, height: headR * 0.5))
        ctx.fillEllipse(in: CGRect(x: cx + headR * 0.1, y: headY + headR * 0.3, width: headR * 0.5, height: headR * 0.4))
        ctx.restoreGState()

        // Tusks/horns — curved shapes on top
        for dir: CGFloat in [-1, 1] {
            let hornX = cx + dir * headR * 0.5
            let hornBaseY = headY + headR * 0.75
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))  // outline
            ctx.move(to: CGPoint(x: hornX - s * 0.02, y: hornBaseY))
            ctx.addLine(to: CGPoint(x: hornX + dir * s * 0.06, y: hornBaseY + s * 0.12))
            ctx.addLine(to: CGPoint(x: hornX + s * 0.02, y: hornBaseY))
            ctx.fillPath()
            ctx.setFillColor(CGColor(gray: 0.88, alpha: 1))  // ivory
            ctx.move(to: CGPoint(x: hornX - s * 0.012, y: hornBaseY))
            ctx.addLine(to: CGPoint(x: hornX + dir * s * 0.05, y: hornBaseY + s * 0.10))
            ctx.addLine(to: CGPoint(x: hornX + s * 0.012, y: hornBaseY))
            ctx.fillPath()
        }

        // Mask eye holes — reveal blue eyes underneath
        let eyeY = headY + headR * 0.05
        for dir: CGFloat in [-1, 1] {
            let ex = cx + dir * headR * 0.35
            let ew = headR * 0.22, eh = headR * 0.18
            // Dark hole
            ctx.setFillColor(CGColor(gray: 0.05, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex - ew, y: eyeY - eh, width: ew * 2, height: eh * 2))
            // Blue eyes peeking through
            ctx.setFillColor(CGColor(red: 0.30, green: 0.55, blue: 0.85, alpha: 1))
            let iw = ew * 0.6, ih = eh * 0.6
            ctx.fillEllipse(in: CGRect(x: ex - iw, y: eyeY - ih, width: iw * 2, height: ih * 2))
            // Highlight
            ctx.setFillColor(CGColor(gray: 1, alpha: 0.8))
            ctx.fillEllipse(in: CGRect(x: ex + ew * 0.15, y: eyeY + eh * 0.1, width: ew * 0.3, height: eh * 0.3))
        }

        // Snout area of mask
        let snoutY = headY - headR * 0.2
        ctx.setFillColor(boarDark)
        ctx.fillEllipse(in: CGRect(x: cx - headR * 0.2, y: snoutY - headR * 0.12, width: headR * 0.4, height: headR * 0.2))
        // Nostrils
        ctx.setFillColor(CGColor(gray: 0.15, alpha: 1))
        for dir: CGFloat in [-1, 1] {
            ctx.fillEllipse(in: CGRect(x: cx + dir * headR * 0.08 - s * 0.01, y: snoutY - s * 0.01, width: s * 0.02, height: s * 0.015))
        }
    }

    // MARK: - Giyu

    private static func drawGiyu(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2
        let headR = s * 0.32, headY = s * 0.62
        let bodyW = s * 0.28, bodyH = s * 0.22, bodyY = s * 0.25

        let skin = CGColor(red: 0.90, green: 0.80, blue: 0.68, alpha: 1)
        let deepRed = CGColor(red: 0.55, green: 0.15, blue: 0.18, alpha: 1)
        let deepBlue = CGColor(red: 0.18, green: 0.25, blue: 0.50, alpha: 1)
        let hairBlack = CGColor(gray: 0.10, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW, h: s * 0.04)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: CGColor(gray: 0.15, alpha: 1), size: s)

        // Body — half red/half geometric pattern haori (split down middle)
        let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH)
        outlinedEllipse(ctx, rect: bodyRect, fill: deepRed, outline: ol)

        // Right half — deep blue geometric
        ctx.saveGState()
        ctx.addEllipse(in: bodyRect)
        ctx.clip()
        ctx.setFillColor(deepBlue)
        ctx.fill(CGRect(x: cx, y: bodyY - bodyH / 2, width: bodyW / 2, height: bodyH))
        // Yellow/green geometric lines
        ctx.setStrokeColor(CGColor(red: 0.65, green: 0.60, blue: 0.25, alpha: 0.5))
        ctx.setLineWidth(s * 0.005)
        for i in 0..<4 {
            let lx = cx + CGFloat(i) * bodyW * 0.12
            ctx.move(to: CGPoint(x: lx, y: bodyY - bodyH / 2))
            ctx.addLine(to: CGPoint(x: lx, y: bodyY + bodyH / 2))
        }
        ctx.strokePath()
        ctx.restoreGState()

        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: deepRed, size: s)

        // Head
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: skin, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // Black hair — tied back, long bangs
        ctx.saveGState()
        ctx.addEllipse(in: headRect)
        ctx.clip()
        ctx.setFillColor(hairBlack)
        ctx.fill(CGRect(x: cx - headR, y: headY + headR * 0.05, width: headR * 2, height: headR))
        ctx.restoreGState()

        // Side bangs hanging
        ctx.setFillColor(hairBlack)
        ctx.fillEllipse(in: CGRect(x: cx - headR * 0.85, y: headY - headR * 0.3, width: s * 0.04, height: headR * 0.7))

        // Ponytail behind
        ctx.setFillColor(hairBlack)
        ctx.fillEllipse(in: CGRect(x: cx + headR * 0.4, y: headY + headR * 0.5, width: headR * 0.3, height: headR * 0.5))

        // Stoic eyes — deep blue
        drawAnimeEyes(ctx, cx: cx, headY: headY, headR: headR, size: s,
                      irisColor: CGColor(red: 0.20, green: 0.30, blue: 0.60, alpha: 1))

        // Straight mouth (stoic)
        ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
        ctx.setLineWidth(max(s * 0.015, 1))
        ctx.move(to: CGPoint(x: cx - headR * 0.1, y: headY - headR * 0.35))
        ctx.addLine(to: CGPoint(x: cx + headR * 0.1, y: headY - headR * 0.35))
        ctx.strokePath()
    }

    // MARK: - Shinobu

    private static func drawShinobu(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2
        let headR = s * 0.30, headY = s * 0.60
        let bodyW = s * 0.26, bodyH = s * 0.20, bodyY = s * 0.25

        let skin = CGColor(red: 0.92, green: 0.82, blue: 0.72, alpha: 1)
        let purple = CGColor(red: 0.55, green: 0.35, blue: 0.65, alpha: 1)
        let lightPurple = CGColor(red: 0.70, green: 0.55, blue: 0.80, alpha: 1)
        let hairBlack = CGColor(red: 0.12, green: 0.08, blue: 0.18, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW, h: s * 0.04)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: CGColor(gray: 0.15, alpha: 1), size: s)

        // Body — purple butterfly-pattern haori
        let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH)
        outlinedEllipse(ctx, rect: bodyRect, fill: purple, outline: ol)

        // Butterfly wing hints on haori
        ctx.saveGState()
        ctx.addEllipse(in: bodyRect)
        ctx.clip()
        ctx.setFillColor(lightPurple)
        // Small wing shapes
        for dir: CGFloat in [-1, 1] {
            let wx = cx + dir * bodyW * 0.15
            ctx.fillEllipse(in: CGRect(x: wx - s * 0.02, y: bodyY - bodyH * 0.1, width: s * 0.04, height: s * 0.035))
        }
        ctx.restoreGState()

        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: purple, size: s)

        // Head
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: skin, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // Black hair with purple tint
        ctx.saveGState()
        ctx.addEllipse(in: headRect)
        ctx.clip()
        ctx.setFillColor(hairBlack)
        ctx.fill(CGRect(x: cx - headR, y: headY + headR * 0.05, width: headR * 2, height: headR))
        ctx.restoreGState()

        // Side bangs — straight cut
        ctx.setFillColor(hairBlack)
        for dir: CGFloat in [-1, 1] {
            ctx.fill(CGRect(x: cx + dir * headR * 0.55 - s * 0.025, y: headY - headR * 0.1, width: s * 0.05, height: headR * 0.5))
        }

        // Butterfly hair ornament — distinctive feature
        let bfX = cx + headR * 0.3, bfY = headY + headR * 0.85
        // Wings
        for dir: CGFloat in [-1, 1] {
            ctx.setFillColor(CGColor(red: 0.65, green: 0.40, blue: 0.80, alpha: 0.9))
            let wingW = headR * 0.2, wingH = headR * 0.15
            ctx.fillEllipse(in: CGRect(x: bfX + dir * wingW * 0.3 - wingW / 2, y: bfY - wingH / 2, width: wingW, height: wingH))
        }
        // Body of butterfly
        ctx.setFillColor(CGColor(gray: 0.2, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: bfX - s * 0.005, y: bfY - s * 0.01, width: s * 0.01, height: s * 0.02))

        // Eyes — purple iris
        drawAnimeEyes(ctx, cx: cx, headY: headY, headR: headR, size: s,
                      irisColor: CGColor(red: 0.55, green: 0.30, blue: 0.65, alpha: 1))

        // Gentle smile
        drawSmile(ctx, cx: cx, headY: headY, headR: headR, size: s)

        // Blush
        ctx.setFillColor(CGColor(red: 0.95, green: 0.55, blue: 0.55, alpha: 0.25))
        for dir: CGFloat in [-1, 1] {
            ctx.fillEllipse(in: CGRect(x: cx + dir * headR * 0.45 - headR * 0.1, y: headY - headR * 0.25, width: headR * 0.2, height: headR * 0.12))
        }
    }

    // MARK: - Rengoku

    private static func drawRengoku(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2
        let headR = s * 0.33, headY = s * 0.62
        let bodyW = s * 0.28, bodyH = s * 0.22, bodyY = s * 0.25

        let skin = CGColor(red: 0.92, green: 0.80, blue: 0.65, alpha: 1)
        let flameRed = CGColor(red: 0.85, green: 0.25, blue: 0.12, alpha: 1)
        let flameYellow = CGColor(red: 0.95, green: 0.75, blue: 0.15, alpha: 1)
        let flameOrange = CGColor(red: 0.92, green: 0.50, blue: 0.12, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW, h: s * 0.04)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: CGColor(gray: 0.15, alpha: 1), size: s)

        // Body — flame haori (white with red flame pattern at bottom)
        let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH)
        outlinedEllipse(ctx, rect: bodyRect, fill: CGColor(gray: 0.95, alpha: 1), outline: ol)

        // Flame pattern on lower body
        ctx.saveGState()
        ctx.addEllipse(in: bodyRect)
        ctx.clip()
        ctx.setFillColor(flameRed)
        // Wavy flame shapes
        for i in 0..<5 {
            let fx = bodyRect.minX + CGFloat(i) * bodyW * 0.25
            let peakH = bodyH * 0.35 + CGFloat(i % 2) * bodyH * 0.1
            ctx.move(to: CGPoint(x: fx, y: bodyY - bodyH / 2))
            ctx.addQuadCurve(to: CGPoint(x: fx + bodyW * 0.25, y: bodyY - bodyH / 2),
                             control: CGPoint(x: fx + bodyW * 0.125, y: bodyY - bodyH / 2 + peakH))
            ctx.fillPath()
        }
        ctx.setFillColor(flameYellow)
        for i in 0..<5 {
            let fx = bodyRect.minX + CGFloat(i) * bodyW * 0.25
            let peakH = bodyH * 0.18 + CGFloat(i % 2) * bodyH * 0.05
            ctx.move(to: CGPoint(x: fx, y: bodyY - bodyH / 2))
            ctx.addQuadCurve(to: CGPoint(x: fx + bodyW * 0.25, y: bodyY - bodyH / 2),
                             control: CGPoint(x: fx + bodyW * 0.125, y: bodyY - bodyH / 2 + peakH))
            ctx.fillPath()
        }
        ctx.restoreGState()

        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: CGColor(gray: 0.95, alpha: 1), size: s)

        // Head
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: skin, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // Flame-like hair — red at roots, yellow at tips, wild and tall
        drawSpikyHair(ctx, cx: cx, headY: headY, headR: headR, hairColor: flameRed, spikes: 7, spikeH: 0.22, spread: 0.6, size: s)
        // Yellow tips on top of red spikes
        drawSpikyHair(ctx, cx: cx, headY: headY + s * 0.04, headR: headR * 0.9, hairColor: flameYellow, spikes: 5, spikeH: 0.20, spread: 0.5, size: s)

        // Hair cap
        ctx.saveGState()
        ctx.addEllipse(in: headRect)
        ctx.clip()
        ctx.setFillColor(flameRed)
        ctx.fill(CGRect(x: cx - headR, y: headY + headR * 0.05, width: headR * 2, height: headR))
        ctx.setFillColor(flameYellow)
        ctx.fill(CGRect(x: cx - headR * 0.7, y: headY + headR * 0.5, width: headR * 1.4, height: headR * 0.45))
        ctx.restoreGState()

        // Thick eyebrows (Rengoku's distinctive feature)
        ctx.setFillColor(flameOrange)
        for dir: CGFloat in [-1, 1] {
            let bx = cx + dir * headR * 0.35
            let by = headY + headR * 0.18
            ctx.saveGState()
            ctx.translateBy(x: bx, y: by)
            ctx.rotate(by: dir * 0.15)
            ctx.fill(CGRect(x: -headR * 0.15, y: -headR * 0.04, width: headR * 0.3, height: headR * 0.08))
            ctx.restoreGState()
        }

        // Eyes — golden/amber (flame Hashira)
        drawAnimeEyes(ctx, cx: cx, headY: headY, headR: headR, size: s,
                      irisColor: CGColor(red: 0.90, green: 0.65, blue: 0.15, alpha: 1))

        // Confident grin
        ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
        ctx.setLineWidth(max(s * 0.018, 1.2))
        ctx.setLineCap(.round)
        ctx.addArc(center: CGPoint(x: cx, y: headY - headR * 0.25),
                   radius: headR * 0.2, startAngle: -.pi * 0.1, endAngle: -.pi * 0.9, clockwise: true)
        ctx.strokePath()
        ctx.setLineCap(.butt)
    }

    // MARK: - Muzan

    private static func drawMuzan(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2
        let headR = s * 0.32, headY = s * 0.62
        let bodyW = s * 0.28, bodyH = s * 0.22, bodyY = s * 0.25

        let paleSkin = CGColor(red: 0.95, green: 0.90, blue: 0.88, alpha: 1)
        let suitBlack = CGColor(gray: 0.10, alpha: 1)
        let hairBlack = CGColor(gray: 0.05, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW, h: s * 0.04)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: suitBlack, size: s)

        // Body — black suit
        let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH)
        outlinedEllipse(ctx, rect: bodyRect, fill: suitBlack, outline: ol)

        // White shirt collar peek
        ctx.setFillColor(CGColor(gray: 0.92, alpha: 1))
        let collarW = bodyW * 0.15
        ctx.move(to: CGPoint(x: cx - collarW, y: bodyY + bodyH * 0.35))
        ctx.addLine(to: CGPoint(x: cx, y: bodyY + bodyH * 0.1))
        ctx.addLine(to: CGPoint(x: cx + collarW, y: bodyY + bodyH * 0.35))
        ctx.fillPath()

        // Red tie
        ctx.setFillColor(CGColor(red: 0.70, green: 0.12, blue: 0.12, alpha: 1))
        ctx.move(to: CGPoint(x: cx - s * 0.01, y: bodyY + bodyH * 0.2))
        ctx.addLine(to: CGPoint(x: cx, y: bodyY - bodyH * 0.1))
        ctx.addLine(to: CGPoint(x: cx + s * 0.01, y: bodyY + bodyH * 0.2))
        ctx.fillPath()

        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: suitBlack, size: s)

        // Head — very pale
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: paleSkin, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // Slicked black hair — smooth, wavy
        ctx.saveGState()
        ctx.addEllipse(in: headRect)
        ctx.clip()
        ctx.setFillColor(hairBlack)
        ctx.fill(CGRect(x: cx - headR, y: headY + headR * 0.1, width: headR * 2, height: headR))
        ctx.restoreGState()

        // Hair curls down one side
        ctx.setFillColor(hairBlack)
        ctx.fillEllipse(in: CGRect(x: cx - headR * 0.9, y: headY - headR * 0.2, width: s * 0.04, height: headR * 0.6))

        // Red eyes — menacing, slitted
        let eyeY = headY - headR * 0.02
        for dir: CGFloat in [-1, 1] {
            let ex = cx + dir * headR * 0.38
            let ew = headR * 0.24, eh = headR * 0.28
            // Dark socket
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex - ew - 1.5, y: eyeY - eh - 1.5, width: (ew + 1.5) * 2, height: (eh + 1.5) * 2))
            // White sclera
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex - ew, y: eyeY - eh, width: ew * 2, height: eh * 2))
            // Red iris
            ctx.setFillColor(CGColor(red: 0.85, green: 0.12, blue: 0.15, alpha: 1))
            let iw = ew * 0.7, ih = eh * 0.75
            ctx.fillEllipse(in: CGRect(x: ex - iw, y: eyeY - ih, width: iw * 2, height: ih * 2))
            // Vertical slit pupil
            ctx.setFillColor(CGColor(gray: 0.05, alpha: 1))
            ctx.fill(CGRect(x: ex - ew * 0.1, y: eyeY - eh * 0.6, width: ew * 0.2, height: eh * 1.2))
            // Highlight
            ctx.setFillColor(CGColor(gray: 1, alpha: 0.7))
            ctx.fillEllipse(in: CGRect(x: ex + ew * 0.2, y: eyeY + eh * 0.15, width: ew * 0.25, height: eh * 0.25))
        }

        // Thin menacing smile
        ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
        ctx.setLineWidth(max(s * 0.012, 1))
        ctx.setLineCap(.round)
        let mouthY = headY - headR * 0.38
        ctx.addArc(center: CGPoint(x: cx, y: mouthY + headR * 0.15),
                   radius: headR * 0.18, startAngle: -.pi * 0.1, endAngle: -.pi * 0.9, clockwise: true)
        ctx.strokePath()
        ctx.setLineCap(.butt)
    }
}
