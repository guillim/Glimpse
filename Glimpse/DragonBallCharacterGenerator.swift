// Glimpse/DragonBallCharacterGenerator.swift
import AppKit

/// Generates chibi Dragon Ball Z characters procedurally using Core Graphics.
/// Same architecture as CharacterGenerator — deterministic mapping from sessionID.
enum DragonBallCharacterGenerator {

    // MARK: - Character Definitions

    enum Character: Int, CaseIterable {
        case goku = 0
        case vegeta
        case piccolo
        case gohan
        case frieza
        case krillin
        case trunks
        case buu
    }

    static func color(for sessionID: String) -> NSColor {
        let ch = character(for: sessionID)
        switch ch {
        case .goku:    return NSColor(red: 0.95, green: 0.55, blue: 0.15, alpha: 1)  // orange gi
        case .vegeta:  return NSColor(red: 0.25, green: 0.30, blue: 0.65, alpha: 1)  // blue bodysuit
        case .piccolo: return NSColor(red: 0.30, green: 0.60, blue: 0.30, alpha: 1)  // green skin
        case .gohan:   return NSColor(red: 0.50, green: 0.28, blue: 0.55, alpha: 1)  // purple gi
        case .frieza:  return NSColor(red: 0.60, green: 0.40, blue: 0.70, alpha: 1)  // purple accents
        case .krillin: return NSColor(red: 0.95, green: 0.60, blue: 0.20, alpha: 1)  // orange gi
        case .trunks:  return NSColor(red: 0.55, green: 0.45, blue: 0.75, alpha: 1)  // lavender hair
        case .buu:     return NSColor(red: 0.90, green: 0.55, blue: 0.65, alpha: 1)  // pink skin
        }
    }

    // MARK: - Cache & RNG

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

    private static func seed(from sessionID: String) -> UInt64 {
        var hash: UInt64 = 5381
        for byte in sessionID.utf8 { hash = hash &* 33 &+ UInt64(byte) }
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
        case .goku:    drawGoku(ctx, size: size)
        case .vegeta:  drawVegeta(ctx, size: size)
        case .piccolo: drawPiccolo(ctx, size: size)
        case .gohan:   drawGohan(ctx, size: size)
        case .frieza:  drawFrieza(ctx, size: size)
        case .krillin: drawKrillin(ctx, size: size)
        case .trunks:  drawTrunks(ctx, size: size)
        case .buu:     drawBuu(ctx, size: size)
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

    // MARK: - Goku

    private static func drawGoku(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2
        let headR = s * 0.32, headY = s * 0.62
        let bodyW = s * 0.28, bodyH = s * 0.22, bodyY = s * 0.25

        let skin = CGColor(red: 0.92, green: 0.80, blue: 0.65, alpha: 1)
        let orangeGi = CGColor(red: 0.95, green: 0.55, blue: 0.15, alpha: 1)
        let blueSash = CGColor(red: 0.20, green: 0.35, blue: 0.70, alpha: 1)
        let black = CGColor(gray: 0.10, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW, h: s * 0.04)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: orangeGi, size: s)

        // Body — orange gi
        let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH)
        outlinedEllipse(ctx, rect: bodyRect, fill: orangeGi, outline: ol)

        // Blue belt/sash
        let beltH = bodyH * 0.16
        outlinedRect(ctx, rect: CGRect(x: cx - bodyW * 0.4, y: bodyY - beltH / 2, width: bodyW * 0.8, height: beltH),
                     fill: blueSash, outline: ol * 0.5)

        // Kanji symbol on chest
        ctx.setStrokeColor(blueSash)
        ctx.setLineWidth(max(s * 0.012, 1))
        ctx.setLineCap(.round)
        let kanjiX = cx, kanjiY = bodyY + bodyH * 0.18
        let kanjiS = s * 0.025
        // Simplified kanji "亀" (turtle) — cross-like shape
        ctx.move(to: CGPoint(x: kanjiX - kanjiS, y: kanjiY))
        ctx.addLine(to: CGPoint(x: kanjiX + kanjiS, y: kanjiY))
        ctx.move(to: CGPoint(x: kanjiX, y: kanjiY - kanjiS))
        ctx.addLine(to: CGPoint(x: kanjiX, y: kanjiY + kanjiS))
        ctx.move(to: CGPoint(x: kanjiX - kanjiS * 0.7, y: kanjiY + kanjiS * 0.5))
        ctx.addLine(to: CGPoint(x: kanjiX + kanjiS * 0.7, y: kanjiY + kanjiS * 0.5))
        ctx.strokePath()
        ctx.setLineCap(.butt)

        // Blue wristbands on arms
        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: orangeGi, size: s)
        for dir: CGFloat in [-1, 1] {
            let ax = cx + dir * (bodyW / 2 + s * 0.04)
            let bandY = bodyY - bodyH * 0.08
            ctx.setFillColor(blueSash)
            ctx.fillEllipse(in: CGRect(x: ax - s * 0.032, y: bandY - s * 0.015, width: s * 0.064, height: s * 0.03))
        }

        // Head
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: skin, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // Black spiky hair — tall, 6 big spikes going upward
        drawSpikyHair(ctx, cx: cx, headY: headY, headR: headR, hairColor: black, spikes: 6, spikeH: 0.24, spread: 0.65, size: s)

        // Hair cap
        ctx.saveGState()
        ctx.addEllipse(in: headRect)
        ctx.clip()
        ctx.setFillColor(black)
        ctx.fill(CGRect(x: cx - headR, y: headY + headR * 0.1, width: headR * 2, height: headR))
        ctx.restoreGState()

        // Eyes — dark brown/black
        drawAnimeEyes(ctx, cx: cx, headY: headY, headR: headR, size: s,
                      irisColor: CGColor(red: 0.15, green: 0.12, blue: 0.10, alpha: 1))

        // Determined smile
        drawSmile(ctx, cx: cx, headY: headY, headR: headR, size: s)
    }

    // MARK: - Vegeta

    private static func drawVegeta(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2
        let headR = s * 0.32, headY = s * 0.62
        let bodyW = s * 0.28, bodyH = s * 0.22, bodyY = s * 0.25

        let skin = CGColor(red: 0.92, green: 0.80, blue: 0.65, alpha: 1)
        let bluesuit = CGColor(red: 0.18, green: 0.25, blue: 0.55, alpha: 1)
        let armorWhite = CGColor(red: 0.92, green: 0.90, blue: 0.85, alpha: 1)
        let black = CGColor(gray: 0.08, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW, h: s * 0.04)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: armorWhite, size: s)

        // Body — blue bodysuit
        let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH)
        outlinedEllipse(ctx, rect: bodyRect, fill: bluesuit, outline: ol)

        // White armor chest plate on top
        ctx.saveGState()
        ctx.addEllipse(in: bodyRect)
        ctx.clip()
        ctx.setFillColor(armorWhite)
        let armorRect = CGRect(x: cx - bodyW * 0.38, y: bodyY - bodyH * 0.05, width: bodyW * 0.76, height: bodyH * 0.55)
        ctx.fillEllipse(in: armorRect)
        // Yellow trim on armor
        ctx.setStrokeColor(CGColor(red: 0.85, green: 0.75, blue: 0.25, alpha: 1))
        ctx.setLineWidth(s * 0.008)
        ctx.strokeEllipse(in: armorRect.insetBy(dx: s * 0.005, dy: s * 0.005))
        ctx.restoreGState()

        // White gloves on arms
        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: armorWhite, size: s)

        // Head
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: skin, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // Flame-shaped upright black hair — tall, narrow, pointed up (widow's peak)
        ctx.setFillColor(black)
        let hairBaseY = headY + headR * 0.55
        // Central tall flame
        ctx.move(to: CGPoint(x: cx - headR * 0.4, y: hairBaseY))
        ctx.addLine(to: CGPoint(x: cx - headR * 0.15, y: hairBaseY + s * 0.32))
        ctx.addLine(to: CGPoint(x: cx, y: hairBaseY + s * 0.28))
        ctx.addLine(to: CGPoint(x: cx + headR * 0.15, y: hairBaseY + s * 0.32))
        ctx.addLine(to: CGPoint(x: cx + headR * 0.4, y: hairBaseY))
        ctx.fillPath()
        // Side flames
        for dir: CGFloat in [-1, 1] {
            ctx.move(to: CGPoint(x: cx + dir * headR * 0.35, y: hairBaseY))
            ctx.addLine(to: CGPoint(x: cx + dir * headR * 0.55, y: hairBaseY + s * 0.18))
            ctx.addLine(to: CGPoint(x: cx + dir * headR * 0.7, y: hairBaseY - s * 0.02))
            ctx.fillPath()
        }

        // Hair cap — widow's peak
        ctx.saveGState()
        ctx.addEllipse(in: headRect)
        ctx.clip()
        ctx.setFillColor(black)
        ctx.fill(CGRect(x: cx - headR, y: headY + headR * 0.1, width: headR * 2, height: headR))
        // Widow's peak — triangle dipping down center
        ctx.move(to: CGPoint(x: cx - headR * 0.3, y: headY + headR * 0.25))
        ctx.addLine(to: CGPoint(x: cx, y: headY + headR * 0.05))
        ctx.addLine(to: CGPoint(x: cx + headR * 0.3, y: headY + headR * 0.25))
        ctx.fillPath()
        ctx.restoreGState()

        // Dark, narrow eyes — proud/scowling
        drawAnimeEyes(ctx, cx: cx, headY: headY, headR: headR, size: s,
                      irisColor: CGColor(red: 0.12, green: 0.10, blue: 0.10, alpha: 1), spacing: 0.38)

        // Angry/proud eyebrows
        ctx.setFillColor(black)
        for dir: CGFloat in [-1, 1] {
            let bx = cx + dir * headR * 0.35
            let by = headY + headR * 0.2
            ctx.saveGState()
            ctx.translateBy(x: bx, y: by)
            ctx.rotate(by: -dir * 0.25)
            ctx.fill(CGRect(x: -headR * 0.14, y: -headR * 0.03, width: headR * 0.28, height: headR * 0.06))
            ctx.restoreGState()
        }

        // Scowl — straight/slightly frowning mouth
        ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
        ctx.setLineWidth(max(s * 0.015, 1))
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: cx - headR * 0.12, y: headY - headR * 0.35))
        ctx.addLine(to: CGPoint(x: cx + headR * 0.12, y: headY - headR * 0.33))
        ctx.strokePath()
        ctx.setLineCap(.butt)
    }

    // MARK: - Piccolo

    private static func drawPiccolo(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2
        let headR = s * 0.32, headY = s * 0.62
        let bodyW = s * 0.28, bodyH = s * 0.22, bodyY = s * 0.25

        let greenSkin = CGColor(red: 0.40, green: 0.65, blue: 0.35, alpha: 1)
        let purpleGi = CGColor(red: 0.45, green: 0.25, blue: 0.55, alpha: 1)
        let whiteCape = CGColor(red: 0.92, green: 0.90, blue: 0.85, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW, h: s * 0.04)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: CGColor(red: 0.55, green: 0.40, blue: 0.25, alpha: 1), size: s)

        // Body — purple gi
        let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH)
        outlinedEllipse(ctx, rect: bodyRect, fill: purpleGi, outline: ol)

        // White cape draped over shoulders
        ctx.saveGState()
        ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
        let capeOutRect = CGRect(x: cx - bodyW * 0.55 - ol, y: bodyY - bodyH * 0.1 - ol, width: bodyW * 1.1 + ol * 2, height: bodyH * 0.65 + ol * 2)
        ctx.fillEllipse(in: capeOutRect)
        ctx.setFillColor(whiteCape)
        ctx.fillEllipse(in: CGRect(x: cx - bodyW * 0.55, y: bodyY - bodyH * 0.1, width: bodyW * 1.1, height: bodyH * 0.65))
        ctx.restoreGState()

        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: purpleGi, size: s)

        // Head — green skin
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: greenSkin, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // White turban on top
        let turbanR = headR * 0.75
        let turbanY = headY + headR * 0.55
        outlinedEllipse(ctx, rect: CGRect(x: cx - turbanR, y: turbanY - turbanR * 0.5, width: turbanR * 2, height: turbanR * 1.2),
                        fill: whiteCape, outline: ol)
        // Turban front piece
        ctx.setFillColor(whiteCape)
        ctx.fillEllipse(in: CGRect(x: cx - headR * 0.25, y: turbanY + turbanR * 0.3, width: headR * 0.5, height: headR * 0.3))

        // Two antennae on forehead
        ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
        ctx.setLineWidth(max(s * 0.012, 1))
        ctx.setLineCap(.round)
        for dir: CGFloat in [-1, 1] {
            let antBaseX = cx + dir * headR * 0.15
            let antBaseY = headY + headR * 0.7
            ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
            ctx.setLineWidth(max(s * 0.015, 1.2))
            ctx.move(to: CGPoint(x: antBaseX, y: antBaseY))
            ctx.addLine(to: CGPoint(x: antBaseX + dir * headR * 0.2, y: antBaseY + s * 0.08))
            ctx.strokePath()
            // Antenna tip
            ctx.setFillColor(greenSkin)
            ctx.fillEllipse(in: CGRect(x: antBaseX + dir * headR * 0.2 - s * 0.008, y: antBaseY + s * 0.08 - s * 0.008, width: s * 0.016, height: s * 0.016))
        }
        ctx.setLineCap(.butt)

        // Pointed ears
        for dir: CGFloat in [-1, 1] {
            let earX = cx + dir * headR * 0.9
            let earY = headY + headR * 0.05
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.move(to: CGPoint(x: earX, y: earY - s * 0.02))
            ctx.addLine(to: CGPoint(x: earX + dir * s * 0.04, y: earY + s * 0.02))
            ctx.addLine(to: CGPoint(x: earX, y: earY + s * 0.02))
            ctx.fillPath()
            ctx.setFillColor(greenSkin)
            ctx.move(to: CGPoint(x: earX, y: earY - s * 0.012))
            ctx.addLine(to: CGPoint(x: earX + dir * s * 0.03, y: earY + s * 0.015))
            ctx.addLine(to: CGPoint(x: earX, y: earY + s * 0.012))
            ctx.fillPath()
        }

        // Serious expression — narrow eyes
        drawAnimeEyes(ctx, cx: cx, headY: headY, headR: headR, size: s,
                      irisColor: CGColor(red: 0.12, green: 0.10, blue: 0.08, alpha: 1))

        // Serious straight mouth
        ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
        ctx.setLineWidth(max(s * 0.015, 1))
        ctx.move(to: CGPoint(x: cx - headR * 0.1, y: headY - headR * 0.35))
        ctx.addLine(to: CGPoint(x: cx + headR * 0.1, y: headY - headR * 0.35))
        ctx.strokePath()
    }

    // MARK: - Gohan

    private static func drawGohan(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2
        let headR = s * 0.32, headY = s * 0.62
        let bodyW = s * 0.28, bodyH = s * 0.22, bodyY = s * 0.25

        let skin = CGColor(red: 0.92, green: 0.80, blue: 0.65, alpha: 1)
        let purpleGi = CGColor(red: 0.50, green: 0.28, blue: 0.55, alpha: 1)
        let redBelt = CGColor(red: 0.80, green: 0.20, blue: 0.20, alpha: 1)
        let black = CGColor(gray: 0.10, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW, h: s * 0.04)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: CGColor(gray: 0.15, alpha: 1), size: s)

        // Body — purple gi
        let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH)
        outlinedEllipse(ctx, rect: bodyRect, fill: purpleGi, outline: ol)

        // Red belt
        let beltH = bodyH * 0.15
        outlinedRect(ctx, rect: CGRect(x: cx - bodyW * 0.4, y: bodyY - beltH / 2, width: bodyW * 0.8, height: beltH),
                     fill: redBelt, outline: ol * 0.5)

        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: purpleGi, size: s)

        // Head
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: skin, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // Short neat black hair with slight spikes
        drawSpikyHair(ctx, cx: cx, headY: headY, headR: headR, hairColor: black, spikes: 5, spikeH: 0.14, spread: 0.55, size: s)

        // Hair cap
        ctx.saveGState()
        ctx.addEllipse(in: headRect)
        ctx.clip()
        ctx.setFillColor(black)
        ctx.fill(CGRect(x: cx - headR, y: headY + headR * 0.15, width: headR * 2, height: headR))
        ctx.restoreGState()

        // Gentle eyes — dark brown
        drawAnimeEyes(ctx, cx: cx, headY: headY, headR: headR, size: s,
                      irisColor: CGColor(red: 0.20, green: 0.15, blue: 0.10, alpha: 1))

        // Gentle smile
        drawSmile(ctx, cx: cx, headY: headY, headR: headR, size: s)

        // Slight blush (gentle character)
        ctx.setFillColor(CGColor(red: 0.95, green: 0.55, blue: 0.55, alpha: 0.2))
        for dir: CGFloat in [-1, 1] {
            ctx.fillEllipse(in: CGRect(x: cx + dir * headR * 0.45 - headR * 0.1, y: headY - headR * 0.25, width: headR * 0.2, height: headR * 0.1))
        }
    }

    // MARK: - Frieza

    private static func drawFrieza(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2
        let headR = s * 0.32, headY = s * 0.62
        let bodyW = s * 0.26, bodyH = s * 0.20, bodyY = s * 0.25

        let whiteSkin = CGColor(red: 0.95, green: 0.93, blue: 0.92, alpha: 1)
        let purple = CGColor(red: 0.55, green: 0.30, blue: 0.65, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW, h: s * 0.04)

        // Tail curling behind (drawn before body)
        ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
        ctx.setLineWidth(max(s * 0.02, 1.5))
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: cx + bodyW * 0.3, y: bodyY - bodyH * 0.2))
        ctx.addQuadCurve(to: CGPoint(x: cx + bodyW * 0.7, y: bodyY + bodyH * 0.3),
                         control: CGPoint(x: cx + bodyW * 0.8, y: bodyY - bodyH * 0.3))
        ctx.strokePath()
        ctx.setStrokeColor(whiteSkin)
        ctx.setLineWidth(max(s * 0.012, 1))
        ctx.move(to: CGPoint(x: cx + bodyW * 0.3, y: bodyY - bodyH * 0.2))
        ctx.addQuadCurve(to: CGPoint(x: cx + bodyW * 0.7, y: bodyY + bodyH * 0.3),
                         control: CGPoint(x: cx + bodyW * 0.8, y: bodyY - bodyH * 0.3))
        ctx.strokePath()
        ctx.setLineCap(.butt)

        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: whiteSkin, size: s)

        // Body — white with purple accents
        let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH)
        outlinedEllipse(ctx, rect: bodyRect, fill: whiteSkin, outline: ol)

        // Purple shoulder accents
        ctx.saveGState()
        ctx.addEllipse(in: bodyRect)
        ctx.clip()
        ctx.setFillColor(purple)
        for dir: CGFloat in [-1, 1] {
            ctx.fillEllipse(in: CGRect(x: cx + dir * bodyW * 0.25 - s * 0.03, y: bodyY + bodyH * 0.15, width: s * 0.06, height: s * 0.06))
        }
        ctx.restoreGState()

        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: whiteSkin, size: s)

        // Head — white with purple dome
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: whiteSkin, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // Purple dome on top of head
        ctx.saveGState()
        ctx.addEllipse(in: headRect)
        ctx.clip()
        ctx.setFillColor(purple)
        ctx.fill(CGRect(x: cx - headR, y: headY + headR * 0.25, width: headR * 2, height: headR))
        ctx.restoreGState()

        // Horns on each side
        for dir: CGFloat in [-1, 1] {
            let hornX = cx + dir * headR * 0.6
            let hornBaseY = headY + headR * 0.65
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.move(to: CGPoint(x: hornX - s * 0.015, y: hornBaseY))
            ctx.addLine(to: CGPoint(x: hornX + dir * s * 0.04, y: hornBaseY + s * 0.06))
            ctx.addLine(to: CGPoint(x: hornX + s * 0.015, y: hornBaseY))
            ctx.fillPath()
            ctx.setFillColor(CGColor(red: 0.88, green: 0.85, blue: 0.78, alpha: 1))
            ctx.move(to: CGPoint(x: hornX - s * 0.008, y: hornBaseY))
            ctx.addLine(to: CGPoint(x: hornX + dir * s * 0.032, y: hornBaseY + s * 0.05))
            ctx.addLine(to: CGPoint(x: hornX + s * 0.008, y: hornBaseY))
            ctx.fillPath()
        }

        // Red eyes — menacing
        drawAnimeEyes(ctx, cx: cx, headY: headY, headR: headR, size: s,
                      irisColor: CGColor(red: 0.85, green: 0.15, blue: 0.15, alpha: 1))

        // No nose — just two small dots
        ctx.setFillColor(CGColor(gray: 0.3, alpha: 1))
        for dir: CGFloat in [-1, 1] {
            ctx.fillEllipse(in: CGRect(x: cx + dir * headR * 0.08 - s * 0.005, y: headY - headR * 0.18, width: s * 0.01, height: s * 0.01))
        }

        // Menacing smirk — thin, slightly upturned
        ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
        ctx.setLineWidth(max(s * 0.012, 1))
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: cx - headR * 0.12, y: headY - headR * 0.33))
        ctx.addQuadCurve(to: CGPoint(x: cx + headR * 0.12, y: headY - headR * 0.33),
                         control: CGPoint(x: cx, y: headY - headR * 0.40))
        ctx.strokePath()
        ctx.setLineCap(.butt)
    }

    // MARK: - Krillin

    private static func drawKrillin(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2
        let headR = s * 0.34, headY = s * 0.60
        let bodyW = s * 0.28, bodyH = s * 0.20, bodyY = s * 0.25

        let skin = CGColor(red: 0.92, green: 0.80, blue: 0.65, alpha: 1)
        let orangeGi = CGColor(red: 0.95, green: 0.55, blue: 0.15, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW, h: s * 0.04)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: orangeGi, size: s)

        // Body — orange gi (like Goku)
        let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH)
        outlinedEllipse(ctx, rect: bodyRect, fill: orangeGi, outline: ol)

        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: orangeGi, size: s)

        // Head — bald, slightly larger proportioned (short character)
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: skin, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // Six dots on forehead (3x2 grid) — Krillin's distinctive mark
        ctx.setFillColor(CGColor(red: 0.60, green: 0.40, blue: 0.30, alpha: 0.8))
        let dotR = s * 0.012
        let dotSpacingX = headR * 0.18
        let dotSpacingY = headR * 0.16
        let dotCenterY = headY + headR * 0.4
        for row in 0..<2 {
            for col in 0..<3 {
                let dx = cx + (CGFloat(col) - 1) * dotSpacingX
                let dy = dotCenterY + CGFloat(row) * dotSpacingY
                ctx.fillEllipse(in: CGRect(x: dx - dotR, y: dy - dotR, width: dotR * 2, height: dotR * 2))
            }
        }

        // Eyes — dark, wide and friendly (no nose)
        drawAnimeEyes(ctx, cx: cx, headY: headY, headR: headR, size: s,
                      irisColor: CGColor(red: 0.15, green: 0.12, blue: 0.10, alpha: 1))

        // No nose — flat face (just skip nose entirely, it's a Krillin thing)

        // Friendly wide smile
        ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
        ctx.setLineWidth(max(s * 0.018, 1.2))
        ctx.setLineCap(.round)
        ctx.addArc(center: CGPoint(x: cx, y: headY - headR * 0.28),
                   radius: headR * 0.18, startAngle: -.pi * 0.1, endAngle: -.pi * 0.9, clockwise: true)
        ctx.strokePath()
        ctx.setLineCap(.butt)
    }

    // MARK: - Trunks

    private static func drawTrunks(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2
        let headR = s * 0.32, headY = s * 0.62
        let bodyW = s * 0.28, bodyH = s * 0.22, bodyY = s * 0.25

        let skin = CGColor(red: 0.92, green: 0.80, blue: 0.68, alpha: 1)
        let blueJacket = CGColor(red: 0.30, green: 0.42, blue: 0.72, alpha: 1)
        let blackShirt = CGColor(gray: 0.12, alpha: 1)
        let lavenderHair = CGColor(red: 0.65, green: 0.50, blue: 0.78, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW, h: s * 0.04)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: CGColor(gray: 0.15, alpha: 1), size: s)

        // Body — black shirt underneath
        let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH)
        outlinedEllipse(ctx, rect: bodyRect, fill: blackShirt, outline: ol)

        // Blue Capsule Corp jacket on top
        ctx.saveGState()
        ctx.addEllipse(in: bodyRect)
        ctx.clip()
        ctx.setFillColor(blueJacket)
        // Jacket covers sides but open in center showing black shirt
        ctx.fill(CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW * 0.35, height: bodyH))
        ctx.fill(CGRect(x: cx + bodyW * 0.15, y: bodyY - bodyH / 2, width: bodyW * 0.35, height: bodyH))
        // Jacket collar
        ctx.fill(CGRect(x: cx - bodyW / 2, y: bodyY + bodyH * 0.25, width: bodyW, height: bodyH * 0.25))
        ctx.restoreGState()

        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: blueJacket, size: s)

        // Sword handle visible over right shoulder
        ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
        let swordX = cx + bodyW * 0.35
        let swordBaseY = bodyY + bodyH * 0.3
        ctx.fill(CGRect(x: swordX - s * 0.008, y: swordBaseY, width: s * 0.016, height: s * 0.18))
        // Sword handle wrap
        ctx.setFillColor(CGColor(red: 0.55, green: 0.35, blue: 0.20, alpha: 1))
        ctx.fill(CGRect(x: swordX - s * 0.01, y: swordBaseY + s * 0.13, width: s * 0.02, height: s * 0.035))
        // Sword guard (cross piece)
        ctx.setFillColor(CGColor(red: 0.75, green: 0.70, blue: 0.55, alpha: 1))
        ctx.fill(CGRect(x: swordX - s * 0.018, y: swordBaseY + s * 0.125, width: s * 0.036, height: s * 0.008))

        // Head
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: skin, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // Lavender bowl-cut hair
        ctx.saveGState()
        ctx.addEllipse(in: headRect)
        ctx.clip()
        ctx.setFillColor(lavenderHair)
        ctx.fill(CGRect(x: cx - headR, y: headY + headR * 0.0, width: headR * 2, height: headR * 1.1))
        ctx.restoreGState()

        // Bowl-cut fringe — rounded hair covering forehead
        ctx.setFillColor(lavenderHair)
        ctx.fillEllipse(in: CGRect(x: cx - headR * 0.85, y: headY + headR * 0.15, width: headR * 1.7, height: headR * 0.7))

        // Side hair strands
        for dir: CGFloat in [-1, 1] {
            ctx.setFillColor(lavenderHair)
            ctx.fillEllipse(in: CGRect(x: cx + dir * headR * 0.65 - s * 0.025, y: headY - headR * 0.15, width: s * 0.05, height: headR * 0.55))
        }

        // Eyes — blue
        drawAnimeEyes(ctx, cx: cx, headY: headY, headR: headR, size: s,
                      irisColor: CGColor(red: 0.25, green: 0.40, blue: 0.75, alpha: 1))

        // Confident smile
        drawSmile(ctx, cx: cx, headY: headY, headR: headR, size: s)
    }

    // MARK: - Buu

    private static func drawBuu(_ ctx: CGContext, size s: CGFloat) {
        let cx = s / 2
        let headR = s * 0.30, headY = s * 0.60
        let bodyW = s * 0.30, bodyH = s * 0.24, bodyY = s * 0.25

        let pinkSkin = CGColor(red: 0.92, green: 0.55, blue: 0.65, alpha: 1)
        let whitePants = CGColor(red: 0.92, green: 0.90, blue: 0.85, alpha: 1)
        let purpleCape = CGColor(red: 0.50, green: 0.30, blue: 0.60, alpha: 1)
        let yellowBoots = CGColor(red: 0.90, green: 0.78, blue: 0.25, alpha: 1)

        drawShadow(ctx, cx: cx, y: bodyY - bodyH / 2 - s * 0.08, w: bodyW, h: s * 0.04)
        drawFeet(ctx, cx: cx, footY: bodyY - bodyH / 2, bodyW: bodyW, fill: yellowBoots, size: s)

        // Body — round/fat, pink with white pants
        let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH)
        outlinedEllipse(ctx, rect: bodyRect, fill: pinkSkin, outline: ol)

        // White pants on lower body
        ctx.saveGState()
        ctx.addEllipse(in: bodyRect)
        ctx.clip()
        ctx.setFillColor(whitePants)
        ctx.fill(CGRect(x: cx - bodyW / 2, y: bodyY - bodyH / 2, width: bodyW, height: bodyH * 0.5))
        ctx.restoreGState()

        // Purple cape behind/on shoulders
        ctx.saveGState()
        ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: cx - bodyW * 0.52 - ol, y: bodyY + bodyH * 0.05 - ol, width: bodyW * 1.04 + ol * 2, height: bodyH * 0.55 + ol * 2))
        ctx.setFillColor(purpleCape)
        ctx.fillEllipse(in: CGRect(x: cx - bodyW * 0.52, y: bodyY + bodyH * 0.05, width: bodyW * 1.04, height: bodyH * 0.55))
        ctx.restoreGState()

        drawArms(ctx, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, fill: pinkSkin, size: s)

        // Head — pink, round
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR * 2, height: headR * 2)
        outlinedEllipse(ctx, rect: headRect, fill: pinkSkin, outline: ol)
        headHighlight(ctx, headRect: headRect, cx: cx, headY: headY, headR: headR)

        // Antenna tentacle on top, drooping backward
        ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
        ctx.setLineWidth(max(s * 0.025, 2))
        ctx.setLineCap(.round)
        let antBaseX = cx
        let antBaseY = headY + headR * 0.9
        ctx.move(to: CGPoint(x: antBaseX, y: antBaseY))
        ctx.addQuadCurve(to: CGPoint(x: antBaseX + headR * 0.6, y: antBaseY + s * 0.02),
                         control: CGPoint(x: antBaseX + headR * 0.2, y: antBaseY + s * 0.12))
        ctx.strokePath()
        // Pink fill for antenna
        ctx.setStrokeColor(pinkSkin)
        ctx.setLineWidth(max(s * 0.016, 1.2))
        ctx.move(to: CGPoint(x: antBaseX, y: antBaseY))
        ctx.addQuadCurve(to: CGPoint(x: antBaseX + headR * 0.6, y: antBaseY + s * 0.02),
                         control: CGPoint(x: antBaseX + headR * 0.2, y: antBaseY + s * 0.12))
        ctx.strokePath()
        ctx.setLineCap(.butt)

        // Small eyes
        let eyeY = headY + headR * 0.05
        for dir: CGFloat in [-1, 1] {
            let ex = cx + dir * headR * 0.3
            let ew = headR * 0.15, eh = headR * 0.18
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex - ew - 1, y: eyeY - eh - 1, width: (ew + 1) * 2, height: (eh + 1) * 2))
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ex - ew, y: eyeY - eh, width: ew * 2, height: eh * 2))
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            let pw = ew * 0.55, ph = eh * 0.6
            ctx.fillEllipse(in: CGRect(x: ex - pw, y: eyeY - ph, width: pw * 2, height: ph * 2))
            // Highlight
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            let hlR = ew * 0.35
            ctx.fillEllipse(in: CGRect(x: ex + ew * 0.15, y: eyeY + eh * 0.1, width: hlR, height: hlR))
        }

        // Wide innocent smile — big open mouth
        ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
        let mouthY = headY - headR * 0.3
        let mouthW = headR * 0.35, mouthH = headR * 0.2
        ctx.fillEllipse(in: CGRect(x: cx - mouthW, y: mouthY - mouthH, width: mouthW * 2, height: mouthH * 2))
        // Pink inside
        ctx.setFillColor(CGColor(red: 0.85, green: 0.40, blue: 0.50, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: cx - mouthW * 0.8, y: mouthY - mouthH * 0.7, width: mouthW * 1.6, height: mouthH * 1.4))
    }
}
