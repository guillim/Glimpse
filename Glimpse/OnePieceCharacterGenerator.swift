// Glimpse/OnePieceCharacterGenerator.swift
import AppKit

/// Generates chibi One Piece characters procedurally using Core Graphics.
/// Same architecture as DemonSlayerCharacterGenerator — deterministic mapping from sessionID.
enum OnePieceCharacterGenerator {

    // MARK: - Character Definitions

    enum Character: Int, CaseIterable {
        case luffy = 0
        case zoro
        case nami
        case sanji
        case chopper
        case robin
        case franky
        case brook
    }

    static func color(for sessionID: String) -> NSColor {
        let ch = character(for: sessionID)
        switch ch {
        case .luffy:   return NSColor(red: 0.85, green: 0.20, blue: 0.15, alpha: 1)  // red vest
        case .zoro:    return NSColor(red: 0.25, green: 0.55, blue: 0.25, alpha: 1)  // green
        case .nami:    return NSColor(red: 0.92, green: 0.55, blue: 0.20, alpha: 1)  // orange hair
        case .sanji:   return NSColor(red: 0.20, green: 0.20, blue: 0.25, alpha: 1)  // black suit
        case .chopper: return NSColor(red: 0.85, green: 0.55, blue: 0.65, alpha: 1)  // pink
        case .robin:   return NSColor(red: 0.40, green: 0.30, blue: 0.55, alpha: 1)  // purple
        case .franky:  return NSColor(red: 0.25, green: 0.50, blue: 0.85, alpha: 1)  // blue
        case .brook:   return NSColor(red: 0.90, green: 0.90, blue: 0.88, alpha: 1)  // bone white
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
        case .luffy:   drawLuffy(ctx, size: size)
        case .zoro:    drawZoro(ctx, size: size)
        case .nami:    drawNami(ctx, size: size)
        case .sanji:   drawSanji(ctx, size: size)
        case .chopper: drawChopper(ctx, size: size)
        case .robin:   drawRobin(ctx, size: size)
        case .franky:  drawFranky(ctx, size: size)
        case .brook:   drawBrook(ctx, size: size)
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

    // MARK: - Luffy

    private static func drawLuffy(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2
        let headR = s * 0.32, headY = s * 0.62
        let bodyW = s * 0.28, bodyH = s * 0.22, bodyY = s * 0.25

        let skin = CGColor(red: 0.92, green: 0.78, blue: 0.65, alpha: 1)
        let red = CGColor(red: 0.85, green: 0.15, blue: 0.12, alpha: 1)
        let blue = CGColor(red: 0.20, green: 0.30, blue: 0.65, alpha: 1)
        let hairBlack = CGColor(gray: 0.10, alpha: 1)
        let strawYellow = CGColor(red: 0.95, green: 0.85, blue: 0.40, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW, h: s * 0.04)

        // Sandals — tan/brown
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: CGColor(red: 0.70, green: 0.55, blue: 0.35, alpha: 1), size: s)

        // Body — red vest open over chest
        let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH)
        outlinedEllipse(ctx, rect: bodyRect, fill: skin, outline: ol)

        // Blue shorts on lower half
        ctx.saveGState()
        ctx.addEllipse(in: bodyRect)
        ctx.clip()
        ctx.setFillColor(blue)
        ctx.fill(CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH * 0.5))
        ctx.restoreGState()

        // Red vest — two vertical strips on either side of chest
        ctx.saveGState()
        ctx.addEllipse(in: bodyRect)
        ctx.clip()
        ctx.setFillColor(red)
        ctx.fill(CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW * 0.28, height: bodyH))
        ctx.fill(CGRect(x: cx + bodyW / 2 - bodyW * 0.28, y: bodyY - bodyH / 2, width: bodyW * 0.28, height: bodyH))
        ctx.restoreGState()

        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: red, size: s)

        // Head
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: skin, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // Black spiky hair under hat
        drawSpikyHair(ctx, cx: cx, headY: headY, headR: headR, hairColor: hairBlack, spikes: 7, spikeH: 0.12, spread: 0.8, size: s)

        // Hair cap
        ctx.saveGState()
        ctx.addEllipse(in: headRect)
        ctx.clip()
        ctx.setFillColor(hairBlack)
        ctx.fill(CGRect(x: cx - headR, y: headY + headR * 0.15, width: headR * 2, height: headR))
        ctx.restoreGState()

        // Straw hat — wide brim
        let hatBrimY = headY + headR * 0.55
        let hatBrimW = headR * 1.5
        let hatBrimH = headR * 0.18
        // Brim outline
        ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: cx - hatBrimW - ol, y: hatBrimY - hatBrimH / 2 - ol, width: (hatBrimW + ol) * 2, height: hatBrimH + ol * 2))
        // Brim fill
        ctx.setFillColor(strawYellow)
        ctx.fillEllipse(in: CGRect(x: cx - hatBrimW, y: hatBrimY - hatBrimH / 2, width: hatBrimW * 2, height: hatBrimH))

        // Hat dome
        let hatDomeW = headR * 0.9
        let hatDomeH = headR * 0.55
        ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: cx - hatDomeW - ol, y: hatBrimY - ol, width: (hatDomeW + ol) * 2, height: hatDomeH + ol * 2))
        ctx.setFillColor(strawYellow)
        ctx.fillEllipse(in: CGRect(x: cx - hatDomeW, y: hatBrimY, width: hatDomeW * 2, height: hatDomeH))

        // Red band on hat
        ctx.setFillColor(red)
        ctx.fill(CGRect(x: cx - hatDomeW * 0.85, y: hatBrimY + hatDomeH * 0.15, width: hatDomeW * 1.7, height: hatDomeH * 0.2))

        // Scar under left eye — X-shaped
        let scarX = cx - headR * 0.35
        let scarY = headY - headR * 0.18
        ctx.setStrokeColor(CGColor(red: 0.70, green: 0.25, blue: 0.20, alpha: 0.9))
        ctx.setLineWidth(s * 0.012)
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: scarX - headR * 0.06, y: scarY + headR * 0.06))
        ctx.addLine(to: CGPoint(x: scarX + headR * 0.06, y: scarY - headR * 0.06))
        ctx.strokePath()
        ctx.move(to: CGPoint(x: scarX + headR * 0.06, y: scarY + headR * 0.06))
        ctx.addLine(to: CGPoint(x: scarX - headR * 0.06, y: scarY - headR * 0.06))
        ctx.strokePath()
        ctx.setLineCap(.butt)

        // Eyes — dark brown
        drawAnimeEyes(ctx, cx: cx, headY: headY, headR: headR, size: s,
                      irisColor: CGColor(red: 0.25, green: 0.15, blue: 0.10, alpha: 1))

        // Big grin
        ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
        ctx.setLineWidth(max(s * 0.02, 1.2))
        ctx.setLineCap(.round)
        ctx.addArc(center: CGPoint(x: cx, y: headY - headR * 0.22),
                   radius: headR * 0.25, startAngle: -.pi * 0.05, endAngle: -.pi * 0.95, clockwise: true)
        ctx.strokePath()
        ctx.setLineCap(.butt)
    }

    // MARK: - Zoro

    private static func drawZoro(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2
        let headR = s * 0.32, headY = s * 0.62
        let bodyW = s * 0.28, bodyH = s * 0.22, bodyY = s * 0.25

        let skin = CGColor(red: 0.90, green: 0.78, blue: 0.65, alpha: 1)
        let green = CGColor(red: 0.25, green: 0.55, blue: 0.25, alpha: 1)
        let greenDark = CGColor(red: 0.18, green: 0.40, blue: 0.18, alpha: 1)
        let hairGreen = CGColor(red: 0.30, green: 0.60, blue: 0.30, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW, h: s * 0.04)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: CGColor(gray: 0.15, alpha: 1), size: s)

        // Katanas crossed on back — draw before body
        let katanaColor = CGColor(gray: 0.75, alpha: 1)
        let katanaHandleColor = CGColor(red: 0.35, green: 0.15, blue: 0.15, alpha: 1)
        for dir: CGFloat in [-1, 1] {
            // Blade
            ctx.setStrokeColor(katanaColor)
            ctx.setLineWidth(s * 0.012)
            ctx.move(to: CGPoint(x: cx + dir * bodyW * 0.1, y: bodyY - bodyH * 0.1))
            ctx.addLine(to: CGPoint(x: cx + dir * bodyW * 0.45, y: bodyY + bodyH * 0.9))
            ctx.strokePath()
            // Handle
            ctx.setStrokeColor(katanaHandleColor)
            ctx.setLineWidth(s * 0.018)
            ctx.move(to: CGPoint(x: cx + dir * bodyW * 0.45, y: bodyY + bodyH * 0.9))
            ctx.addLine(to: CGPoint(x: cx + dir * bodyW * 0.52, y: bodyY + bodyH * 1.15))
            ctx.strokePath()
        }

        // Body — green haori/robe
        let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH)
        outlinedEllipse(ctx, rect: bodyRect, fill: green, outline: ol)

        // Darker sash/belt
        ctx.saveGState()
        ctx.addEllipse(in: bodyRect)
        ctx.clip()
        ctx.setFillColor(greenDark)
        ctx.fill(CGRect(x: cx - bodyW / 2, y: bodyY - bodyH * 0.08, width: bodyW, height: bodyH * 0.16))
        ctx.restoreGState()

        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: green, size: s)

        // Head
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: skin, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // Short green hair
        ctx.saveGState()
        ctx.addEllipse(in: headRect)
        ctx.clip()
        ctx.setFillColor(hairGreen)
        ctx.fill(CGRect(x: cx - headR, y: headY + headR * 0.15, width: headR * 2, height: headR))
        ctx.restoreGState()

        // Short spiky green hair on top
        drawSpikyHair(ctx, cx: cx, headY: headY, headR: headR, hairColor: hairGreen, spikes: 5, spikeH: 0.08, spread: 0.5, size: s)

        // Left eye closed (scar) — draw line instead of eye
        let eyeY = headY - headR * 0.05
        let leftEyeX = cx - headR * 0.4
        ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
        ctx.setLineWidth(max(s * 0.015, 1))
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: leftEyeX - headR * 0.12, y: eyeY))
        ctx.addLine(to: CGPoint(x: leftEyeX + headR * 0.12, y: eyeY))
        ctx.strokePath()
        // Scar over closed left eye
        ctx.setStrokeColor(CGColor(red: 0.70, green: 0.25, blue: 0.20, alpha: 0.8))
        ctx.setLineWidth(s * 0.01)
        ctx.move(to: CGPoint(x: leftEyeX, y: eyeY + headR * 0.15))
        ctx.addLine(to: CGPoint(x: leftEyeX, y: eyeY - headR * 0.15))
        ctx.strokePath()
        ctx.setLineCap(.butt)

        // Right eye — dark gray/black iris
        let rightEyeX = cx + headR * 0.4
        let ew = headR * 0.26, eh = headR * 0.35
        ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: rightEyeX - ew - 1.5, y: eyeY - eh - 1.5, width: (ew + 1.5) * 2, height: (eh + 1.5) * 2))
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: rightEyeX - ew, y: eyeY - eh, width: ew * 2, height: eh * 2))
        ctx.setFillColor(CGColor(red: 0.25, green: 0.25, blue: 0.25, alpha: 1))
        let iw = ew * 0.8, ih = eh * 0.8
        ctx.fillEllipse(in: CGRect(x: rightEyeX - iw, y: eyeY - ih - eh * 0.05, width: iw * 2, height: ih * 2))
        ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
        let pw = ew * 0.4, ph = eh * 0.45
        ctx.fillEllipse(in: CGRect(x: rightEyeX - pw, y: eyeY - ph - eh * 0.1, width: pw * 2, height: ph * 2))
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        let hlR = ew * 0.32
        ctx.fillEllipse(in: CGRect(x: rightEyeX + ew * 0.15 - hlR / 2, y: eyeY + eh * 0.15 - hlR / 2, width: hlR, height: hlR))

        // Serious straight mouth
        ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
        ctx.setLineWidth(max(s * 0.015, 1))
        ctx.move(to: CGPoint(x: cx - headR * 0.12, y: headY - headR * 0.35))
        ctx.addLine(to: CGPoint(x: cx + headR * 0.12, y: headY - headR * 0.35))
        ctx.strokePath()
    }

    // MARK: - Nami

    private static func drawNami(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2
        let headR = s * 0.30, headY = s * 0.60
        let bodyW = s * 0.26, bodyH = s * 0.20, bodyY = s * 0.25

        let skin = CGColor(red: 0.94, green: 0.82, blue: 0.72, alpha: 1)
        let orangeHair = CGColor(red: 0.92, green: 0.55, blue: 0.18, alpha: 1)
        let bikiniBlue = CGColor(red: 0.30, green: 0.50, blue: 0.80, alpha: 1)
        let jeansBlue = CGColor(red: 0.30, green: 0.40, blue: 0.65, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW, h: s * 0.04)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: CGColor(red: 0.75, green: 0.55, blue: 0.35, alpha: 1), size: s)

        // Body
        let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH)
        outlinedEllipse(ctx, rect: bodyRect, fill: skin, outline: ol)

        // Jeans on lower half
        ctx.saveGState()
        ctx.addEllipse(in: bodyRect)
        ctx.clip()
        ctx.setFillColor(jeansBlue)
        ctx.fill(CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH * 0.5))
        ctx.restoreGState()

        // Bikini top — blue with white stripes
        ctx.saveGState()
        ctx.addEllipse(in: bodyRect)
        ctx.clip()
        ctx.setFillColor(bikiniBlue)
        ctx.fill(CGRect(x: cx - bodyW / 2, y: bodyY + bodyH * 0.1, width: bodyW, height: bodyH * 0.25))
        // White stripes
        ctx.setFillColor(CGColor(gray: 0.95, alpha: 1))
        ctx.fill(CGRect(x: cx - bodyW / 2, y: bodyY + bodyH * 0.18, width: bodyW, height: bodyH * 0.06))
        ctx.restoreGState()

        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: skin, size: s)

        // Log pose on left wrist
        let logX = cx - (bodyW / 2 + s * 0.04)
        let logY = bodyY - bodyH * 0.05
        ctx.setFillColor(CGColor(red: 0.65, green: 0.50, blue: 0.30, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: logX - s * 0.02, y: logY - s * 0.02, width: s * 0.04, height: s * 0.04))
        ctx.setFillColor(CGColor(gray: 0.85, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: logX - s * 0.012, y: logY - s * 0.012, width: s * 0.024, height: s * 0.024))

        // Head
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: skin, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // Long orange hair
        ctx.saveGState()
        ctx.addEllipse(in: headRect)
        ctx.clip()
        ctx.setFillColor(orangeHair)
        ctx.fill(CGRect(x: cx - headR, y: headY + headR * 0.05, width: headR * 2, height: headR))
        ctx.restoreGState()

        // Hair flowing down sides
        for dir: CGFloat in [-1, 1] {
            let hx = cx + dir * headR * 0.75
            ctx.setFillColor(orangeHair)
            ctx.fillEllipse(in: CGRect(x: hx - s * 0.035, y: headY - headR * 0.6, width: s * 0.07, height: headR * 1.2))
        }

        // Eyes — blue
        drawAnimeEyes(ctx, cx: cx, headY: headY, headR: headR, size: s,
                      irisColor: CGColor(red: 0.20, green: 0.40, blue: 0.80, alpha: 1))
        drawSmile(ctx, cx: cx, headY: headY, headR: headR, size: s)
    }

    // MARK: - Sanji

    private static func drawSanji(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2
        let headR = s * 0.32, headY = s * 0.62
        let bodyW = s * 0.28, bodyH = s * 0.22, bodyY = s * 0.25

        let skin = CGColor(red: 0.92, green: 0.80, blue: 0.68, alpha: 1)
        let suitBlack = CGColor(gray: 0.12, alpha: 1)
        let shirtBlue = CGColor(red: 0.30, green: 0.40, blue: 0.70, alpha: 1)
        let blondHair = CGColor(red: 0.95, green: 0.85, blue: 0.40, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW, h: s * 0.04)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: suitBlack, size: s)

        // Body — black suit
        let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH)
        outlinedEllipse(ctx, rect: bodyRect, fill: suitBlack, outline: ol)

        // Blue shirt visible in center
        ctx.saveGState()
        ctx.addEllipse(in: bodyRect)
        ctx.clip()
        ctx.setFillColor(shirtBlue)
        ctx.fill(CGRect(x: cx - bodyW * 0.15, y: bodyY - bodyH * 0.1, width: bodyW * 0.3, height: bodyH * 0.6))
        ctx.restoreGState()

        // Tie
        ctx.setFillColor(CGColor(gray: 0.08, alpha: 1))
        ctx.move(to: CGPoint(x: cx - s * 0.008, y: bodyY + bodyH * 0.25))
        ctx.addLine(to: CGPoint(x: cx, y: bodyY - bodyH * 0.05))
        ctx.addLine(to: CGPoint(x: cx + s * 0.008, y: bodyY + bodyH * 0.25))
        ctx.fillPath()

        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: suitBlack, size: s)

        // Head
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: skin, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // Blond hair swept over left eye
        ctx.saveGState()
        ctx.addEllipse(in: headRect)
        ctx.clip()
        ctx.setFillColor(blondHair)
        ctx.fill(CGRect(x: cx - headR, y: headY + headR * 0.05, width: headR * 2, height: headR))
        // Extra hair covering left side of face
        ctx.setFillColor(blondHair)
        ctx.fill(CGRect(x: cx - headR, y: headY - headR * 0.3, width: headR * 0.9, height: headR * 0.8))
        ctx.restoreGState()

        // Side bang hanging down over left eye
        ctx.setFillColor(blondHair)
        ctx.fillEllipse(in: CGRect(x: cx - headR * 0.85, y: headY - headR * 0.5, width: headR * 0.55, height: headR * 1.0))

        // Only right eye visible — blue iris
        let eyeY = headY - headR * 0.05
        let rightEyeX = cx + headR * 0.4
        let ew = headR * 0.26, eh = headR * 0.35
        ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: rightEyeX - ew - 1.5, y: eyeY - eh - 1.5, width: (ew + 1.5) * 2, height: (eh + 1.5) * 2))
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: rightEyeX - ew, y: eyeY - eh, width: ew * 2, height: eh * 2))
        ctx.setFillColor(CGColor(red: 0.25, green: 0.40, blue: 0.70, alpha: 1))
        let iw = ew * 0.8, ih = eh * 0.8
        ctx.fillEllipse(in: CGRect(x: rightEyeX - iw, y: eyeY - ih - eh * 0.05, width: iw * 2, height: ih * 2))
        ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
        let pw = ew * 0.4, ph = eh * 0.45
        ctx.fillEllipse(in: CGRect(x: rightEyeX - pw, y: eyeY - ph - eh * 0.1, width: pw * 2, height: ph * 2))
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        let hlR = ew * 0.32
        ctx.fillEllipse(in: CGRect(x: rightEyeX + ew * 0.15 - hlR / 2, y: eyeY + eh * 0.15 - hlR / 2, width: hlR, height: hlR))

        // Curly eyebrow (spiral) above visible right eye
        ctx.setStrokeColor(blondHair)
        ctx.setLineWidth(max(s * 0.012, 1))
        ctx.setLineCap(.round)
        let browX = rightEyeX
        let browY = eyeY + eh + headR * 0.08
        ctx.addArc(center: CGPoint(x: browX, y: browY),
                   radius: headR * 0.08, startAngle: 0, endAngle: .pi * 1.5, clockwise: false)
        ctx.strokePath()
        ctx.setLineCap(.butt)

        // Small cigarette
        let cigX = cx + headR * 0.15
        let cigY = headY - headR * 0.35
        ctx.setStrokeColor(CGColor(gray: 0.85, alpha: 1))
        ctx.setLineWidth(s * 0.012)
        ctx.move(to: CGPoint(x: cigX, y: cigY))
        ctx.addLine(to: CGPoint(x: cigX + headR * 0.4, y: cigY + headR * 0.05))
        ctx.strokePath()
        // Ember tip
        ctx.setFillColor(CGColor(red: 0.95, green: 0.50, blue: 0.15, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: cigX + headR * 0.38, y: cigY, width: s * 0.015, height: s * 0.015))

        // Cool straight mouth
        ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
        ctx.setLineWidth(max(s * 0.012, 1))
        ctx.move(to: CGPoint(x: cx - headR * 0.05, y: headY - headR * 0.35))
        ctx.addLine(to: CGPoint(x: cx + headR * 0.15, y: headY - headR * 0.35))
        ctx.strokePath()
    }

    // MARK: - Chopper

    private static func drawChopper(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2
        let headR = s * 0.34, headY = s * 0.60
        let bodyW = s * 0.26, bodyH = s * 0.20, bodyY = s * 0.25

        let brownFur = CGColor(red: 0.65, green: 0.45, blue: 0.30, alpha: 1)
        let pinkFur = CGColor(red: 0.90, green: 0.70, blue: 0.65, alpha: 1)
        let blueNose = CGColor(red: 0.30, green: 0.50, blue: 0.85, alpha: 1)
        let hatPink = CGColor(red: 0.85, green: 0.40, blue: 0.50, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW * 0.8, h: s * 0.03)

        // Hooves — dark brown
        let hoofColor = CGColor(red: 0.40, green: 0.28, blue: 0.18, alpha: 1)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW * 0.7, fill: hoofColor, size: s)

        // Body — round, pink/light brown
        let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH)
        outlinedEllipse(ctx, rect: bodyRect, fill: pinkFur, outline: ol)

        // Brown tummy area
        ctx.saveGState()
        ctx.addEllipse(in: bodyRect)
        ctx.clip()
        ctx.setFillColor(brownFur)
        ctx.fillEllipse(in: CGRect(x: cx - bodyW * 0.3, y: bodyY - bodyH * 0.3, width: bodyW * 0.6, height: bodyH * 0.6))
        ctx.restoreGState()

        // Small arms (hoof-like)
        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW * 0.8, bodyH: bodyH, fill: brownFur, size: s)

        // Head — round, pink
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: pinkFur, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // Brown patches on face
        ctx.saveGState()
        ctx.addEllipse(in: headRect)
        ctx.clip()
        ctx.setFillColor(brownFur)
        ctx.fill(CGRect(x: cx - headR, y: headY + headR * 0.3, width: headR * 2, height: headR * 0.7))
        ctx.restoreGState()

        // Pink hat with white X
        let hatY = headY + headR * 0.55
        let hatW = headR * 1.1
        let hatH = headR * 0.55
        // Hat brim
        ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: cx - hatW - ol, y: hatY - ol, width: (hatW + ol) * 2, height: headR * 0.15 + ol * 2))
        ctx.setFillColor(hatPink)
        ctx.fillEllipse(in: CGRect(x: cx - hatW, y: hatY, width: hatW * 2, height: headR * 0.15))
        // Hat dome
        ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: cx - hatW * 0.75 - ol, y: hatY - ol, width: (hatW * 0.75 + ol) * 2, height: hatH + ol * 2))
        ctx.setFillColor(hatPink)
        ctx.fillEllipse(in: CGRect(x: cx - hatW * 0.75, y: hatY, width: hatW * 1.5, height: hatH))

        // White X on hat
        ctx.setStrokeColor(CGColor(gray: 0.95, alpha: 1))
        ctx.setLineWidth(max(s * 0.018, 1.5))
        ctx.setLineCap(.round)
        let xCx = cx
        let xCy = hatY + hatH * 0.45
        let xR = hatH * 0.2
        ctx.move(to: CGPoint(x: xCx - xR, y: xCy - xR))
        ctx.addLine(to: CGPoint(x: xCx + xR, y: xCy + xR))
        ctx.strokePath()
        ctx.move(to: CGPoint(x: xCx + xR, y: xCy - xR))
        ctx.addLine(to: CGPoint(x: xCx - xR, y: xCy + xR))
        ctx.strokePath()
        ctx.setLineCap(.butt)

        // Tiny antlers poking from hat
        let antlerColor = CGColor(red: 0.55, green: 0.38, blue: 0.22, alpha: 1)
        for dir: CGFloat in [-1, 1] {
            let antlerX = cx + dir * headR * 0.35
            let antlerBaseY = hatY + hatH * 0.7
            ctx.setStrokeColor(antlerColor)
            ctx.setLineWidth(s * 0.015)
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: antlerX, y: antlerBaseY))
            ctx.addLine(to: CGPoint(x: antlerX + dir * headR * 0.15, y: antlerBaseY + s * 0.08))
            ctx.strokePath()
            // Branch
            ctx.move(to: CGPoint(x: antlerX + dir * headR * 0.08, y: antlerBaseY + s * 0.05))
            ctx.addLine(to: CGPoint(x: antlerX + dir * headR * 0.22, y: antlerBaseY + s * 0.065))
            ctx.strokePath()
            ctx.setLineCap(.butt)
        }

        // Cute dot eyes
        let eyeY = headY + headR * 0.05
        for dir: CGFloat in [-1, 1] {
            let ex = cx + dir * headR * 0.3
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex - headR * 0.1, y: eyeY - headR * 0.1, width: headR * 0.2, height: headR * 0.2))
            // Tiny highlight
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex + headR * 0.02, y: eyeY + headR * 0.02, width: headR * 0.07, height: headR * 0.07))
        }

        // Blue nose — prominent
        ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: cx - headR * 0.11 - ol, y: headY - headR * 0.18 - ol,
                                    width: headR * 0.22 + ol * 2, height: headR * 0.18 + ol * 2))
        ctx.setFillColor(blueNose)
        ctx.fillEllipse(in: CGRect(x: cx - headR * 0.11, y: headY - headR * 0.18, width: headR * 0.22, height: headR * 0.18))
        // Nose highlight
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.4))
        ctx.fillEllipse(in: CGRect(x: cx - headR * 0.04, y: headY - headR * 0.08, width: headR * 0.06, height: headR * 0.06))

        // Small smile
        ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
        ctx.setLineWidth(max(s * 0.012, 1))
        ctx.setLineCap(.round)
        ctx.addArc(center: CGPoint(x: cx, y: headY - headR * 0.28),
                   radius: headR * 0.08, startAngle: -.pi * 0.15, endAngle: -.pi * 0.85, clockwise: true)
        ctx.strokePath()
        ctx.setLineCap(.butt)
    }

    // MARK: - Robin

    private static func drawRobin(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2
        let headR = s * 0.30, headY = s * 0.62
        let bodyW = s * 0.26, bodyH = s * 0.20, bodyY = s * 0.25

        let skin = CGColor(red: 0.92, green: 0.80, blue: 0.68, alpha: 1)
        let purple = CGColor(red: 0.35, green: 0.25, blue: 0.50, alpha: 1)
        let hairBlack = CGColor(gray: 0.08, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW, h: s * 0.04)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: CGColor(gray: 0.15, alpha: 1), size: s)

        // Body — dark purple outfit
        let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH)
        outlinedEllipse(ctx, rect: bodyRect, fill: purple, outline: ol)

        // Crossed arms — draw arms folded in front
        let armFill = purple
        for dir: CGFloat in [-1, 1] {
            let ax = cx + dir * bodyW * 0.15
            let ay = bodyY + bodyH * 0.05
            ctx.saveGState()
            ctx.translateBy(x: ax, y: ay)
            ctx.rotate(by: dir * (-0.4))
            outlinedEllipse(ctx, rect: CGRect(x: -s * 0.03, y: -s * 0.05, width: s * 0.06, height: s * 0.10), fill: armFill, outline: ol)
            ctx.restoreGState()
        }
        // Hands visible
        for dir: CGFloat in [-1, 1] {
            let hx = cx + dir * bodyW * 0.28
            ctx.setFillColor(skin)
            ctx.fillEllipse(in: CGRect(x: hx - s * 0.02, y: bodyY - s * 0.02, width: s * 0.04, height: s * 0.04))
        }

        // Head
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: skin, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // Long black hair
        ctx.saveGState()
        ctx.addEllipse(in: headRect)
        ctx.clip()
        ctx.setFillColor(hairBlack)
        ctx.fill(CGRect(x: cx - headR, y: headY + headR * 0.05, width: headR * 2, height: headR))
        ctx.restoreGState()

        // Hair flowing down sides — long
        for dir: CGFloat in [-1, 1] {
            let hx = cx + dir * headR * 0.78
            ctx.setFillColor(hairBlack)
            ctx.fillEllipse(in: CGRect(x: hx - s * 0.035, y: headY - headR * 0.7, width: s * 0.07, height: headR * 1.4))
        }

        // Cowgirl hat
        let hatBrimY = headY + headR * 0.65
        let hatBrimW = headR * 1.3
        let hatBrimH = headR * 0.14
        // Brim
        ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: cx - hatBrimW - ol, y: hatBrimY - hatBrimH / 2 - ol,
                                    width: (hatBrimW + ol) * 2, height: hatBrimH + ol * 2))
        ctx.setFillColor(CGColor(red: 0.55, green: 0.35, blue: 0.25, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: cx - hatBrimW, y: hatBrimY - hatBrimH / 2, width: hatBrimW * 2, height: hatBrimH))

        // Hat dome
        let hatDomeW = headR * 0.7
        let hatDomeH = headR * 0.45
        ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: cx - hatDomeW - ol, y: hatBrimY - ol,
                                    width: (hatDomeW + ol) * 2, height: hatDomeH + ol * 2))
        ctx.setFillColor(CGColor(red: 0.55, green: 0.35, blue: 0.25, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: cx - hatDomeW, y: hatBrimY, width: hatDomeW * 2, height: hatDomeH))

        // Eyes — blue, calm
        drawAnimeEyes(ctx, cx: cx, headY: headY, headR: headR, size: s,
                      irisColor: CGColor(red: 0.25, green: 0.40, blue: 0.75, alpha: 1))

        // Calm slight smile
        ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
        ctx.setLineWidth(max(s * 0.012, 1))
        ctx.setLineCap(.round)
        ctx.addArc(center: CGPoint(x: cx, y: headY - headR * 0.3),
                   radius: headR * 0.1, startAngle: -.pi * 0.2, endAngle: -.pi * 0.8, clockwise: true)
        ctx.strokePath()
        ctx.setLineCap(.butt)
    }

    // MARK: - Franky

    private static func drawFranky(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2
        let headR = s * 0.33, headY = s * 0.62
        let bodyW = s * 0.30, bodyH = s * 0.24, bodyY = s * 0.25

        let skin = CGColor(red: 0.90, green: 0.78, blue: 0.65, alpha: 1)
        let blueHair = CGColor(red: 0.20, green: 0.45, blue: 0.85, alpha: 1)
        let hawaiianRed = CGColor(red: 0.85, green: 0.25, blue: 0.20, alpha: 1)
        let metalGray = CGColor(red: 0.65, green: 0.65, blue: 0.70, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW, h: s * 0.04)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: CGColor(red: 0.70, green: 0.55, blue: 0.35, alpha: 1), size: s)

        // Body — red hawaiian shirt
        let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH)
        outlinedEllipse(ctx, rect: bodyRect, fill: hawaiianRed, outline: ol)

        // Flower pattern on shirt
        ctx.saveGState()
        ctx.addEllipse(in: bodyRect)
        ctx.clip()
        ctx.setFillColor(CGColor(red: 0.95, green: 0.85, blue: 0.30, alpha: 0.6))
        let flowerPositions: [(CGFloat, CGFloat)] = [(-0.2, 0.1), (0.15, -0.05), (-0.05, -0.15), (0.2, 0.15)]
        for pos in flowerPositions {
            let fx = cx + bodyW * pos.0
            let fy = bodyY + bodyH * pos.1
            ctx.fillEllipse(in: CGRect(x: fx - s * 0.015, y: fy - s * 0.015, width: s * 0.03, height: s * 0.03))
        }
        ctx.restoreGState()

        // Big arms with star outline on forearms
        for dir: CGFloat in [-1, 1] {
            let ax = cx + dir * (bodyW / 2 + s * 0.05)
            let ay = bodyY + bodyH * 0.05
            ctx.saveGState()
            ctx.translateBy(x: ax, y: ay)
            ctx.rotate(by: dir * 0.25)
            // Bigger arms for Franky
            outlinedEllipse(ctx, rect: CGRect(x: -s * 0.04, y: -s * 0.065, width: s * 0.08, height: s * 0.13), fill: metalGray, outline: ol)
            // Star outline on forearm
            ctx.setStrokeColor(CGColor(red: 0.20, green: 0.45, blue: 0.85, alpha: 0.8))
            ctx.setLineWidth(max(s * 0.008, 0.8))
            let starR = s * 0.018
            let starCY: CGFloat = 0
            for i in 0..<5 {
                let angle = CGFloat(i) * .pi * 2 / 5 - .pi / 2
                let nextAngle = CGFloat(i + 1) * .pi * 2 / 5 - .pi / 2
                let outerX = cos(angle) * starR
                let outerY = starCY + sin(angle) * starR
                let innerAngle = angle + .pi / 5
                let innerX = cos(innerAngle) * starR * 0.4
                let innerY = starCY + sin(innerAngle) * starR * 0.4
                let nextOuterX = cos(nextAngle) * starR
                let nextOuterY = starCY + sin(nextAngle) * starR
                ctx.move(to: CGPoint(x: outerX, y: outerY))
                ctx.addLine(to: CGPoint(x: innerX, y: innerY))
                ctx.addLine(to: CGPoint(x: nextOuterX, y: nextOuterY))
            }
            ctx.strokePath()
            ctx.restoreGState()
        }

        // Head
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: skin, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // Metal chin
        ctx.saveGState()
        ctx.addEllipse(in: headRect)
        ctx.clip()
        ctx.setFillColor(metalGray)
        ctx.fill(CGRect(x: cx - headR * 0.5, y: headY - headR, width: headR, height: headR * 0.5))
        ctx.restoreGState()

        // Blue pompadour — flat top style
        let pompW = headR * 0.85
        let pompH = headR * 0.7
        let pompY = headY + headR * 0.5
        // Outline
        ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
        ctx.fill(CGRect(x: cx - pompW - ol, y: pompY - ol, width: (pompW + ol) * 2, height: pompH + ol * 2))
        // Blue fill — flat top rectangle
        ctx.setFillColor(blueHair)
        ctx.fill(CGRect(x: cx - pompW, y: pompY, width: pompW * 2, height: pompH))
        // Rounded top
        ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: cx - pompW - ol, y: pompY + pompH - headR * 0.15 - ol,
                                    width: (pompW + ol) * 2, height: headR * 0.3 + ol * 2))
        ctx.setFillColor(blueHair)
        ctx.fillEllipse(in: CGRect(x: cx - pompW, y: pompY + pompH - headR * 0.15, width: pompW * 2, height: headR * 0.3))

        // Sunglasses on forehead
        let sgY = headY + headR * 0.35
        ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
        for dir: CGFloat in [-1, 1] {
            let lensX = cx + dir * headR * 0.28
            ctx.fillEllipse(in: CGRect(x: lensX - headR * 0.18, y: sgY - headR * 0.1, width: headR * 0.36, height: headR * 0.2))
        }
        // Bridge
        ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
        ctx.setLineWidth(s * 0.01)
        ctx.move(to: CGPoint(x: cx - headR * 0.1, y: sgY))
        ctx.addLine(to: CGPoint(x: cx + headR * 0.1, y: sgY))
        ctx.strokePath()
        // Lens tint
        ctx.setFillColor(CGColor(red: 0.15, green: 0.15, blue: 0.20, alpha: 0.7))
        for dir: CGFloat in [-1, 1] {
            let lensX = cx + dir * headR * 0.28
            ctx.fillEllipse(in: CGRect(x: lensX - headR * 0.15, y: sgY - headR * 0.07, width: headR * 0.3, height: headR * 0.14))
        }

        // Eyes — small and intense
        let eyeY = headY + headR * 0.08
        for dir: CGFloat in [-1, 1] {
            let ex = cx + dir * headR * 0.3
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex - headR * 0.1, y: eyeY - headR * 0.08, width: headR * 0.2, height: headR * 0.16))
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex - headR * 0.07, y: eyeY - headR * 0.05, width: headR * 0.14, height: headR * 0.1))
            ctx.setFillColor(CGColor(red: 0.20, green: 0.35, blue: 0.65, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex - headR * 0.04, y: eyeY - headR * 0.04, width: headR * 0.08, height: headR * 0.08))
        }

        // Big grin
        ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
        ctx.setLineWidth(max(s * 0.02, 1.2))
        ctx.setLineCap(.round)
        ctx.addArc(center: CGPoint(x: cx, y: headY - headR * 0.2),
                   radius: headR * 0.22, startAngle: -.pi * 0.05, endAngle: -.pi * 0.95, clockwise: true)
        ctx.strokePath()
        ctx.setLineCap(.butt)
    }

    // MARK: - Brook

    private static func drawBrook(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2
        let headR = s * 0.32, headY = s * 0.62
        let bodyW = s * 0.26, bodyH = s * 0.22, bodyY = s * 0.25

        let boneWhite = CGColor(red: 0.95, green: 0.92, blue: 0.88, alpha: 1)
        let suitBlack = CGColor(gray: 0.10, alpha: 1)
        let afroBlack = CGColor(gray: 0.05, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW, h: s * 0.04)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: suitBlack, size: s)

        // Body — black suit, very thin appearance
        let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH)
        outlinedEllipse(ctx, rect: bodyRect, fill: suitBlack, outline: ol)

        // White cravat/ascot
        ctx.setFillColor(CGColor(gray: 0.95, alpha: 1))
        let cravW = bodyW * 0.2
        ctx.move(to: CGPoint(x: cx - cravW, y: bodyY + bodyH * 0.35))
        ctx.addLine(to: CGPoint(x: cx, y: bodyY + bodyH * 0.15))
        ctx.addLine(to: CGPoint(x: cx + cravW, y: bodyY + bodyH * 0.35))
        ctx.fillPath()
        // Cravat bow/puff
        ctx.fillEllipse(in: CGRect(x: cx - cravW * 0.8, y: bodyY + bodyH * 0.22, width: cravW * 1.6, height: bodyH * 0.15))

        // Thin skeletal arms
        for dir: CGFloat in [-1, 1] {
            let ax = cx + dir * (bodyW / 2 + s * 0.035)
            let ay = bodyY + bodyH * 0.05
            ctx.saveGState()
            ctx.translateBy(x: ax, y: ay)
            ctx.rotate(by: dir * 0.3)
            outlinedEllipse(ctx, rect: CGRect(x: -s * 0.022, y: -s * 0.055, width: s * 0.044, height: s * 0.11), fill: suitBlack, outline: ol)
            ctx.restoreGState()
        }

        // Skull head
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: boneWhite, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // Tall afro
        let afroR = headR * 1.1
        let afroY = headY + headR * 0.6
        ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: cx - afroR - ol, y: afroY - afroR * 0.3 - ol,
                                    width: (afroR + ol) * 2, height: (afroR * 1.3 + ol) * 2))
        ctx.setFillColor(afroBlack)
        ctx.fillEllipse(in: CGRect(x: cx - afroR, y: afroY - afroR * 0.3, width: afroR * 2, height: afroR * 2.6))

        // Top hat on afro
        let topHatBrimW = headR * 0.7
        let topHatBrimH = headR * 0.1
        let topHatY = afroY + afroR * 1.9
        // Brim
        ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
        ctx.fill(CGRect(x: cx - topHatBrimW - ol, y: topHatY - ol,
                         width: (topHatBrimW + ol) * 2, height: topHatBrimH + ol * 2))
        ctx.setFillColor(CGColor(gray: 0.15, alpha: 1))
        ctx.fill(CGRect(x: cx - topHatBrimW, y: topHatY, width: topHatBrimW * 2, height: topHatBrimH))
        // Crown
        let topHatCrownW = headR * 0.5
        let topHatCrownH = headR * 0.5
        ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
        ctx.fill(CGRect(x: cx - topHatCrownW - ol, y: topHatY + topHatBrimH - ol,
                         width: (topHatCrownW + ol) * 2, height: topHatCrownH + ol * 2))
        ctx.setFillColor(CGColor(gray: 0.15, alpha: 1))
        ctx.fill(CGRect(x: cx - topHatCrownW, y: topHatY + topHatBrimH, width: topHatCrownW * 2, height: topHatCrownH))

        // Empty eye sockets with glowing dots
        let eyeY = headY + headR * 0.05
        for dir: CGFloat in [-1, 1] {
            let ex = cx + dir * headR * 0.35
            let ew = headR * 0.22, eh = headR * 0.28
            // Dark empty socket
            ctx.setFillColor(CGColor(gray: 0.02, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex - ew, y: eyeY - eh, width: ew * 2, height: eh * 2))
            // Glowing dot inside
            ctx.setFillColor(CGColor(red: 0.70, green: 0.85, blue: 1.0, alpha: 0.9))
            let dotR = ew * 0.3
            ctx.fillEllipse(in: CGRect(x: ex - dotR, y: eyeY - dotR, width: dotR * 2, height: dotR * 2))
        }

        // Nose hole (triangle)
        let noseY = headY - headR * 0.15
        ctx.setFillColor(CGColor(gray: 0.15, alpha: 1))
        ctx.move(to: CGPoint(x: cx, y: noseY + headR * 0.08))
        ctx.addLine(to: CGPoint(x: cx - headR * 0.06, y: noseY - headR * 0.06))
        ctx.addLine(to: CGPoint(x: cx + headR * 0.06, y: noseY - headR * 0.06))
        ctx.fillPath()

        // Skeletal teeth/grin
        ctx.setStrokeColor(CGColor(gray: 0.2, alpha: 1))
        ctx.setLineWidth(max(s * 0.012, 1))
        let teethY = headY - headR * 0.35
        let teethW = headR * 0.35
        ctx.move(to: CGPoint(x: cx - teethW, y: teethY))
        ctx.addLine(to: CGPoint(x: cx + teethW, y: teethY))
        ctx.strokePath()
        // Tooth lines
        ctx.setLineWidth(max(s * 0.008, 0.8))
        for i in 0..<5 {
            let tx = cx - teethW + CGFloat(i) * teethW * 0.5
            ctx.move(to: CGPoint(x: tx, y: teethY + headR * 0.06))
            ctx.addLine(to: CGPoint(x: tx, y: teethY - headR * 0.06))
            ctx.strokePath()
        }
    }
}
