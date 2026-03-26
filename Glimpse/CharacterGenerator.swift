// Glimpse/CharacterGenerator.swift
import AppKit

/// Generates unique chibi-style characters from a session ID seed.
/// Pure function: same sessionID always produces the same CGImage.
///
/// Chibi proportions: oversized head (~60%), tiny body (~40%), big expressive
/// eyes with colored irises, stubby arms and feet. Dark outlines and radial
/// highlights give depth and a hand-drawn feel.
enum CharacterGenerator {
    /// Wraps CGImage for NSCache (requires AnyObject-conforming values).
    private class CGImageBox {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    /// Cache of generated sprites keyed on "sessionID:roundedSize".
    private static let cache = NSCache<NSString, CGImageBox>()

    // MARK: - Traits

    /// All traits derived from a deterministic seed.
    struct Traits {
        enum BodyShape: CaseIterable { case round, oval, squarish, blob }
        enum EyeStyle: CaseIterable { case dot, circle, anime, sleepy }
        enum EarStyle: CaseIterable { case pointy, round, antenna, none }
        enum TailStyle: CaseIterable { case lightning, swirl, flame, none }
        enum MouthStyle: CaseIterable { case smile, open, catMouth, line }
        enum CheekStyle: CaseIterable { case circles, triangles, none }

        let bodyShape: BodyShape
        let bodyColor: NSColor
        let accentColor: NSColor
        let eyeStyle: EyeStyle
        let earStyle: EarStyle
        let tailStyle: TailStyle
        let mouthStyle: MouthStyle
        let cheekStyle: CheekStyle

        /// Body color components as (r, g, b) in 0...1 range.
        var bodyRGB: (CGFloat, CGFloat, CGFloat) {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            bodyColor.usingColorSpace(.deviceRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
            return (r, g, b)
        }
    }

    /// Color palette (must stay in sync with accentColors).
    private static let bodyColors: [NSColor] = [
        NSColor(red: 1.0,  green: 0.8,  blue: 0.02, alpha: 1), // yellow
        NSColor(red: 0.93, green: 0.30, blue: 0.22, alpha: 1), // red
        NSColor(red: 0.30, green: 0.69, blue: 0.93, alpha: 1), // blue
        NSColor(red: 0.30, green: 0.78, blue: 0.47, alpha: 1), // green
        NSColor(red: 0.65, green: 0.45, blue: 0.85, alpha: 1), // purple
        NSColor(red: 0.95, green: 0.55, blue: 0.20, alpha: 1), // orange
        NSColor(red: 0.95, green: 0.55, blue: 0.65, alpha: 1), // pink
        NSColor(red: 0.30, green: 0.78, blue: 0.75, alpha: 1), // teal
        NSColor(red: 0.60, green: 0.45, blue: 0.30, alpha: 1), // brown
    ]

    /// Accent colors — lighter variants for belly patches and ear tips.
    private static let accentColors: [NSColor] = [
        NSColor(red: 1.0,  green: 0.95, blue: 0.7,  alpha: 1), // cream
        NSColor(red: 1.0,  green: 0.75, blue: 0.7,  alpha: 1), // light pink
        NSColor(red: 0.75, green: 0.88, blue: 1.0,  alpha: 1), // light blue
        NSColor(red: 0.75, green: 0.95, blue: 0.8,  alpha: 1), // light green
        NSColor(red: 0.85, green: 0.78, blue: 0.95, alpha: 1), // lavender
        NSColor(red: 1.0,  green: 0.85, blue: 0.65, alpha: 1), // peach
        NSColor(red: 1.0,  green: 0.82, blue: 0.86, alpha: 1), // blush
        NSColor(red: 0.78, green: 0.95, blue: 0.93, alpha: 1), // mint
        NSColor(red: 0.85, green: 0.75, blue: 0.65, alpha: 1), // tan
    ]

    // MARK: - Seeded RNG

    private static func seed(from sessionID: String) -> UInt64 {
        var hash: UInt64 = 5381
        for byte in sessionID.utf8 {
            hash = hash &* 33 &+ UInt64(byte)
        }
        return hash
    }

    private static func pick<T: CaseIterable>(_ seed: inout UInt64) -> T {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        let all = Array(T.allCases)
        return all[Int(seed >> 33) % all.count]
    }

    private static func pickIndex(_ seed: inout UInt64, count: Int) -> Int {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Int(seed >> 33) % count
    }

    /// Derive all traits from a session ID.
    static func traits(for sessionID: String) -> Traits {
        precondition(bodyColors.count == accentColors.count, "bodyColors and accentColors must have equal count")
        var s = seed(from: sessionID)
        let bodyIdx = pickIndex(&s, count: bodyColors.count)
        return Traits(
            bodyShape:  pick(&s),
            bodyColor:  bodyColors[bodyIdx],
            accentColor: accentColors[bodyIdx],
            eyeStyle:   pick(&s),
            earStyle:   pick(&s),
            tailStyle:  pick(&s),
            mouthStyle: pick(&s),
            cheekStyle: pick(&s)
        )
    }

    // MARK: - Outline Helper

    /// Thickness of the dark outline around shapes.
    private static func outlineWidth(for size: CGFloat) -> CGFloat { max(size * 0.025, 1.5) }

    /// Draw an outlined ellipse: dark outline ring then colored fill.
    private static func outlinedEllipse(_ ctx: CGContext, rect: CGRect, fill: CGColor, outline: CGFloat) {
        ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
        ctx.fillEllipse(in: rect.insetBy(dx: -outline, dy: -outline))
        ctx.setFillColor(fill)
        ctx.fillEllipse(in: rect)
    }

    // MARK: - Generate

    /// Generate a chibi character image at the given pixel size.
    static func generate(sessionID: String, size: CGFloat) -> CGImage? {
        let cacheKey = "\(sessionID):\(Int(size.rounded()))" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached.image
        }

        let t = traits(for: sessionID)
        let s = size
        let scale: CGFloat = 2.0  // retina

        guard let ctx = CGContext(
            data: nil,
            width: Int(s * scale),
            height: Int(s * scale),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: 0, y: -s * 0.1)  // shift down so ears aren't clipped at top

        // NOTE: CGContext has origin at bottom-left (y increases upward).
        let cx = s / 2
        let ol = outlineWidth(for: s)

        // Chibi layout: big head in upper 60%, tiny body in lower 40%
        let headR = s * 0.32
        let headY = s * 0.62                       // center of head (upper area)
        let bodyW = s * 0.28, bodyH = s * 0.22
        let bodyY = s * 0.25                        // center of body (lower area)

        // ── 1. Drop shadow ──
        ctx.setFillColor(CGColor(gray: 0, alpha: 0.2))
        let shadowRect = CGRect(x: cx - bodyW * 0.5, y: bodyY - bodyH/2 - s*0.06 - s*0.02,
                                width: bodyW, height: s * 0.04)
        ctx.fillEllipse(in: shadowRect)

        // ── 2. Feet ──
        let footY = bodyY - bodyH/2 - s*0.01
        for dir: CGFloat in [-1, 1] {
            let fx = cx + dir * bodyW * 0.35
            let footRect = CGRect(x: fx - s*0.045, y: footY - s*0.025, width: s*0.09, height: s*0.05)
            outlinedEllipse(ctx, rect: footRect, fill: t.bodyColor.cgColor, outline: ol)
        }

        // ── 3. Ears (behind head) ──
        let earTopY = headY + headR  // top of head in CG coords
        drawEars(ctx, t: t, cx: cx, headTopY: earTopY, headR: headR, size: s, outline: ol)

        // ── 4. Tail (behind body) ──
        drawTail(ctx, t: t, cx: cx, bodyY: bodyY, bodyW: bodyW, bodyH: bodyH, size: s, outline: ol)

        // ── 5. Body (outlined ellipse) ──
        let bodyRect = CGRect(x: cx - bodyW/2, y: bodyY - bodyH/2, width: bodyW, height: bodyH)
        outlinedEllipse(ctx, rect: bodyRect, fill: t.bodyColor.cgColor, outline: ol)

        // Belly patch
        let bellyRect = CGRect(x: cx - bodyW*0.3, y: bodyY - bodyH*0.3, width: bodyW*0.6, height: bodyH*0.55)
        outlinedEllipse(ctx, rect: bellyRect, fill: t.accentColor.cgColor, outline: ol * 0.5)

        // ── 6. Arms (stubby, outlined) ──
        for dir: CGFloat in [-1, 1] {
            let ax = cx + dir * (bodyW/2 + s*0.04)
            let ay = bodyY + bodyH * 0.05
            // Arm is a small rotated ellipse
            ctx.saveGState()
            ctx.translateBy(x: ax, y: ay)
            ctx.rotate(by: dir * 0.3)
            let armRect = CGRect(x: -s*0.03, y: -s*0.055, width: s*0.06, height: s*0.11)
            outlinedEllipse(ctx, rect: armRect, fill: t.bodyColor.cgColor, outline: ol)
            ctx.restoreGState()
        }

        // ── 7. Head (outlined circle) ──
        let headRect = CGRect(x: cx - headR, y: headY - headR, width: headR*2, height: headR*2)
        outlinedEllipse(ctx, rect: headRect, fill: t.bodyColor.cgColor, outline: ol)

        // Head radial highlight
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                CGColor(gray: 1, alpha: 0.2),
                CGColor(gray: 1, alpha: 0.03),
                CGColor(gray: 0, alpha: 0.08)
            ] as CFArray,
            locations: [0, 0.5, 1]
        ) {
            ctx.saveGState()
            // Clip to head circle
            ctx.addEllipse(in: headRect)
            ctx.clip()
            ctx.drawRadialGradient(
                gradient,
                startCenter: CGPoint(x: cx - headR*0.25, y: headY + headR*0.25),
                startRadius: 0,
                endCenter: CGPoint(x: cx, y: headY),
                endRadius: headR,
                options: []
            )
            ctx.restoreGState()
        }

        // ── 8. Eyes (chibi oversized) ──
        drawEyes(ctx, t: t, cx: cx, headY: headY, headR: headR, size: s, outline: ol)

        // ── 9. Mouth ──
        drawMouth(ctx, t: t, cx: cx, headY: headY, headR: headR, size: s)

        // ── 10. Cheeks ──
        drawCheeks(ctx, t: t, cx: cx, headY: headY, headR: headR, size: s)

        let image = ctx.makeImage()
        if let image = image {
            cache.setObject(CGImageBox(image), forKey: cacheKey)
        }
        return image
    }

    // MARK: - Eyes

    private static func drawEyes(_ ctx: CGContext, t: Traits, cx: CGFloat, headY: CGFloat, headR: CGFloat, size s: CGFloat, outline ol: CGFloat) {
        let eyeY = headY - headR * 0.05     // slightly below center of head
        let sp = headR * 0.4                 // eye spacing from center
        let ew = headR * 0.28                // eye width radius
        let eh = headR * 0.35                // eye height radius

        for dir: CGFloat in [-1, 1] {
            let ex = cx + dir * sp

            // Outer socket (dark outline)
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            let socketRect = CGRect(x: ex - ew - ol, y: eyeY - eh - ol, width: (ew + ol)*2, height: (eh + ol)*2)
            ctx.fillEllipse(in: socketRect)

            switch t.eyeStyle {
            case .sleepy:
                // Fill socket with body color, then draw arc
                ctx.setFillColor(t.bodyColor.cgColor)
                ctx.fillEllipse(in: CGRect(x: ex - ew, y: eyeY - eh, width: ew*2, height: eh*2))
                ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
                ctx.setLineWidth(s * 0.02)
                ctx.setLineCap(.round)
                ctx.addArc(center: CGPoint(x: ex, y: eyeY),
                           radius: ew * 0.7,
                           startAngle: .pi * 0.85,  // CG: angles go counterclockwise
                           endAngle: .pi * 0.15,
                           clockwise: true)
                ctx.strokePath()
                ctx.setLineCap(.butt)

            case .dot:
                // Black filled eyes with tiny white highlight
                // (socket already dark, just add highlight)
                ctx.setFillColor(CGColor(gray: 1, alpha: 1))
                let hlR = ew * 0.3
                ctx.fillEllipse(in: CGRect(x: ex + ew*0.15 - hlR/2, y: eyeY + eh*0.2 - hlR/2, width: hlR, height: hlR))

            case .circle:
                // White sclera
                ctx.setFillColor(CGColor(gray: 1, alpha: 1))
                ctx.fillEllipse(in: CGRect(x: ex - ew, y: eyeY - eh, width: ew*2, height: eh*2))
                // Pupil
                let pw = ew * 0.55, ph = eh * 0.55
                ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
                ctx.fillEllipse(in: CGRect(x: ex - pw, y: eyeY - ph, width: pw*2, height: ph*2))
                // Highlight
                let hlR = ew * 0.28
                ctx.setFillColor(CGColor(gray: 1, alpha: 1))
                ctx.fillEllipse(in: CGRect(x: ex + ew*0.2 - hlR/2, y: eyeY + eh*0.25 - hlR/2, width: hlR, height: hlR))

            case .anime:
                // Colored iris matching body
                let (r, g, b) = t.bodyRGB
                let irisColor = CGColor(
                    colorSpace: CGColorSpaceCreateDeviceRGB(),
                    components: [min(r + 0.25, 1), min(g + 0.25, 1), min(b + 0.25, 1), 1]
                ) ?? CGColor(gray: 0.5, alpha: 1)

                ctx.setFillColor(irisColor)
                let iw = ew * 0.85, ih = eh * 0.85
                ctx.fillEllipse(in: CGRect(x: ex - iw, y: eyeY - ih - eh*0.05, width: iw*2, height: ih*2))

                // Dark pupil
                let pw = ew * 0.4, ph = eh * 0.45
                ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
                ctx.fillEllipse(in: CGRect(x: ex - pw, y: eyeY - ph - eh*0.1, width: pw*2, height: ph*2))

                // Big highlight (upper)
                ctx.setFillColor(CGColor(gray: 1, alpha: 1))
                let bigHL = ew * 0.32
                ctx.fillEllipse(in: CGRect(x: ex + ew*0.2 - bigHL/2, y: eyeY + eh*0.2 - bigHL/2, width: bigHL, height: bigHL))
                // Small highlight (lower opposite)
                let smHL = ew * 0.18
                ctx.fillEllipse(in: CGRect(x: ex - ew*0.2 - smHL/2, y: eyeY - eh*0.3 - smHL/2, width: smHL, height: smHL))
            }
        }
    }

    // MARK: - Mouth

    private static func drawMouth(_ ctx: CGContext, t: Traits, cx: CGFloat, headY: CGFloat, headR: CGFloat, size s: CGFloat) {
        let mouthY = headY - headR * 0.4
        ctx.setStrokeColor(CGColor(gray: 0.15, alpha: 1))
        ctx.setLineWidth(s * 0.015)
        ctx.setLineCap(.round)

        switch t.mouthStyle {
        case .smile:
            ctx.addArc(center: CGPoint(x: cx, y: mouthY + s*0.01),
                       radius: headR * 0.12,
                       startAngle: -.pi * 0.15,
                       endAngle: -.pi * 0.85,
                       clockwise: true)
            ctx.strokePath()
        case .open:
            ctx.setFillColor(CGColor(gray: 0.15, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: cx - s*0.025, y: mouthY - s*0.018, width: s*0.05, height: s*0.036))
        case .catMouth:
            let mw = headR * 0.15
            ctx.move(to: CGPoint(x: cx - mw, y: mouthY))
            ctx.addLine(to: CGPoint(x: cx, y: mouthY - s*0.02))
            ctx.addLine(to: CGPoint(x: cx + mw, y: mouthY))
            ctx.strokePath()
        case .line:
            ctx.move(to: CGPoint(x: cx - headR*0.12, y: mouthY))
            ctx.addLine(to: CGPoint(x: cx + headR*0.12, y: mouthY))
            ctx.strokePath()
        }
        ctx.setLineCap(.butt)
    }

    // MARK: - Cheeks

    private static func drawCheeks(_ ctx: CGContext, t: Traits, cx: CGFloat, headY: CGFloat, headR: CGFloat, size s: CGFloat) {
        guard t.cheekStyle != .none else { return }
        let eyeY = headY - headR * 0.05
        let sp = headR * 0.4
        let ew = headR * 0.28
        let cheekY = eyeY - headR * 0.28

        ctx.setFillColor(NSColor(red: 1, green: 0.47, blue: 0.47, alpha: 0.35).cgColor)
        let cr = headR * 0.1
        for dir: CGFloat in [-1, 1] {
            let cheekX = cx + dir * (sp + ew * 0.5)
            switch t.cheekStyle {
            case .circles:
                ctx.fillEllipse(in: CGRect(x: cheekX - cr, y: cheekY - cr, width: cr*2, height: cr*2))
            case .triangles:
                let ts = cr * 0.9
                ctx.move(to: CGPoint(x: cheekX - ts, y: cheekY + ts*0.3))
                ctx.addLine(to: CGPoint(x: cheekX + ts, y: cheekY + ts*0.3))
                ctx.addLine(to: CGPoint(x: cheekX, y: cheekY - ts*0.6))
                ctx.fillPath()
            case .none:
                break
            }
        }
    }

    // MARK: - Ears

    private static func drawEars(_ ctx: CGContext, t: Traits, cx: CGFloat, headTopY: CGFloat, headR: CGFloat, size s: CGFloat, outline ol: CGFloat) {
        switch t.earStyle {
        case .pointy:
            for dir: CGFloat in [-1, 1] {
                let baseX = cx + dir * headR * 0.65
                let baseY = headTopY - headR * 0.15
                let tipX = cx + dir * headR * 0.95
                let tipY = headTopY + s * 0.2
                let innerX = cx + dir * headR * 0.35
                let innerY = headTopY + s * 0.02

                // Outline
                ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
                ctx.move(to: CGPoint(x: baseX - dir*ol, y: baseY))
                ctx.addLine(to: CGPoint(x: tipX + dir*ol, y: tipY + ol))
                ctx.addLine(to: CGPoint(x: innerX, y: innerY))
                ctx.fillPath()

                // Fill
                ctx.setFillColor(t.bodyColor.cgColor)
                ctx.move(to: CGPoint(x: baseX, y: baseY + ol))
                ctx.addLine(to: CGPoint(x: tipX, y: tipY))
                ctx.addLine(to: CGPoint(x: innerX + dir*ol, y: innerY + ol))
                ctx.fillPath()

                // Inner ear accent
                ctx.setFillColor(t.accentColor.cgColor)
                let midX = (baseX + tipX + innerX) / 3
                let midY = (baseY + tipY + innerY) / 3
                let shrink: CGFloat = 0.55
                ctx.move(to: CGPoint(x: midX + (baseX - midX)*shrink, y: midY + (baseY - midY)*shrink))
                ctx.addLine(to: CGPoint(x: midX + (tipX - midX)*shrink, y: midY + (tipY - midY)*shrink))
                ctx.addLine(to: CGPoint(x: midX + (innerX - midX)*shrink, y: midY + (innerY - midY)*shrink))
                ctx.fillPath()
            }

        case .round:
            for dir: CGFloat in [-1, 1] {
                let earCX = cx + dir * headR * 0.85
                let earCY = headTopY - headR * 0.05
                let earW = s * 0.075, earH = s * 0.095
                let earRect = CGRect(x: earCX - earW, y: earCY - earH, width: earW*2, height: earH*2)
                outlinedEllipse(ctx, rect: earRect, fill: t.bodyColor.cgColor, outline: ol)
                // Inner ear
                let innerRect = earRect.insetBy(dx: earW*0.3, dy: earH*0.3)
                ctx.setFillColor(t.accentColor.cgColor)
                ctx.fillEllipse(in: innerRect)
            }

        case .antenna:
            for dir: CGFloat in [-1, 1] {
                let baseX = cx + dir * headR * 0.35
                let baseY = headTopY
                let tipX = cx + dir * headR * 0.5
                let tipY = headTopY + s * 0.18

                // Stalk outline
                ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
                ctx.setLineWidth(s * 0.04)
                ctx.setLineCap(.round)
                ctx.move(to: CGPoint(x: baseX, y: baseY))
                ctx.addLine(to: CGPoint(x: tipX, y: tipY))
                ctx.strokePath()

                // Stalk fill
                ctx.setStrokeColor(t.bodyColor.cgColor)
                ctx.setLineWidth(s * 0.025)
                ctx.move(to: CGPoint(x: baseX, y: baseY))
                ctx.addLine(to: CGPoint(x: tipX, y: tipY))
                ctx.strokePath()
                ctx.setLineCap(.butt)

                // Tip ball
                let tipRect = CGRect(x: tipX - s*0.035, y: tipY - s*0.035, width: s*0.07, height: s*0.07)
                outlinedEllipse(ctx, rect: tipRect, fill: t.accentColor.cgColor, outline: ol)
            }

        case .none:
            break
        }
    }

    // MARK: - Tail

    private static func drawTail(_ ctx: CGContext, t: Traits, cx: CGFloat, bodyY: CGFloat, bodyW: CGFloat, bodyH: CGFloat, size s: CGFloat, outline ol: CGFloat) {
        let tx = cx + bodyW/2 - s*0.01
        let ty = bodyY + bodyH * 0.1

        switch t.tailStyle {
        case .lightning:
            // Outline pass
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.move(to: CGPoint(x: tx - ol, y: ty))
            ctx.addLine(to: CGPoint(x: tx + s*0.17, y: ty + s*0.09))
            ctx.addLine(to: CGPoint(x: tx + s*0.11, y: ty))
            ctx.addLine(to: CGPoint(x: tx + s*0.24, y: ty + s*0.13))
            ctx.addLine(to: CGPoint(x: tx + s*0.14, y: ty + s*0.04))
            ctx.addLine(to: CGPoint(x: tx + s*0.09, y: ty - s*0.05))
            ctx.fillPath()
            // Fill
            ctx.setFillColor(t.bodyColor.cgColor)
            ctx.move(to: CGPoint(x: tx, y: ty))
            ctx.addLine(to: CGPoint(x: tx + s*0.15, y: ty + s*0.08))
            ctx.addLine(to: CGPoint(x: tx + s*0.1, y: ty))
            ctx.addLine(to: CGPoint(x: tx + s*0.22, y: ty + s*0.12))
            ctx.addLine(to: CGPoint(x: tx + s*0.12, y: ty + s*0.04))
            ctx.addLine(to: CGPoint(x: tx + s*0.08, y: ty - s*0.04))
            ctx.fillPath()

        case .swirl:
            ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
            ctx.setLineWidth(s * 0.045)
            ctx.setLineCap(.round)
            ctx.addArc(center: CGPoint(x: tx + s*0.1, y: ty), radius: s*0.08, startAngle: .pi, endAngle: -.pi * 0.3, clockwise: true)
            ctx.strokePath()
            ctx.setStrokeColor(t.bodyColor.cgColor)
            ctx.setLineWidth(s * 0.03)
            ctx.addArc(center: CGPoint(x: tx + s*0.1, y: ty), radius: s*0.08, startAngle: .pi, endAngle: -.pi * 0.3, clockwise: true)
            ctx.strokePath()
            ctx.setLineCap(.butt)

        case .flame:
            // Outline
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.move(to: CGPoint(x: tx - ol, y: ty - s*0.04))
            ctx.addLine(to: CGPoint(x: tx + s*0.14, y: ty + s*0.07))
            ctx.addLine(to: CGPoint(x: tx + s*0.1, y: ty + s*0.01))
            ctx.addLine(to: CGPoint(x: tx + s*0.2, y: ty + s*0.04))
            ctx.addLine(to: CGPoint(x: tx + s*0.07, y: ty - s*0.07))
            ctx.fillPath()
            // Gradient flame fill
            ctx.setFillColor(NSColor(red: 1, green: 0.5, blue: 0.1, alpha: 1).cgColor)
            ctx.move(to: CGPoint(x: tx, y: ty - s*0.03))
            ctx.addLine(to: CGPoint(x: tx + s*0.12, y: ty + s*0.06))
            ctx.addLine(to: CGPoint(x: tx + s*0.08, y: ty - s*0.01))
            ctx.addLine(to: CGPoint(x: tx + s*0.18, y: ty + s*0.03))
            ctx.addLine(to: CGPoint(x: tx + s*0.05, y: ty - s*0.06))
            ctx.fillPath()

        case .none:
            break
        }
    }
}
