// Glimpse/CharacterGenerator.swift
import AppKit

/// Generates unique Pokemon-styled pixel art creatures from a session ID seed.
/// Pure function: same sessionID always produces the same CGImage.
enum CharacterGenerator {
    /// Wraps CGImage for NSCache (requires AnyObject-conforming values).
    private class CGImageBox {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    /// Cache of generated sprites keyed on "sessionID:roundedSize".
    private static let cache = NSCache<NSString, CGImageBox>()

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
    }

    /// Pokemon-inspired color palette (must stay in sync with accentColors).
    private static let bodyColors: [NSColor] = [
        NSColor(red: 1.0,  green: 0.8,  blue: 0.02, alpha: 1), // Pikachu yellow
        NSColor(red: 0.93, green: 0.30, blue: 0.22, alpha: 1), // Charmander red
        NSColor(red: 0.30, green: 0.69, blue: 0.93, alpha: 1), // Squirtle blue
        NSColor(red: 0.30, green: 0.78, blue: 0.47, alpha: 1), // Bulbasaur green
        NSColor(red: 0.65, green: 0.45, blue: 0.85, alpha: 1), // Gengar purple
        NSColor(red: 0.95, green: 0.55, blue: 0.20, alpha: 1), // Charizard orange
        NSColor(red: 0.95, green: 0.55, blue: 0.65, alpha: 1), // Jigglypuff pink
        NSColor(red: 0.30, green: 0.78, blue: 0.75, alpha: 1), // Teal
        NSColor(red: 0.60, green: 0.45, blue: 0.30, alpha: 1), // Eevee brown
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

    /// Deterministic seeded RNG from a session ID string.
    private static func seed(from sessionID: String) -> UInt64 {
        var hash: UInt64 = 5381
        for byte in sessionID.utf8 {
            hash = hash &* 33 &+ UInt64(byte)
        }
        return hash
    }

    /// Pick a random element from a CaseIterable using a mutable seed.
    private static func pick<T: CaseIterable>(_ seed: inout UInt64) -> T {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        let all = Array(T.allCases)
        return all[Int(seed >> 33) % all.count]
    }

    /// Pick an index in a range using a mutable seed.
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

    /// Generate a character image at the given pixel size.
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

        // All drawing is relative to the size
        let cx = s / 2      // center x
        let cy = s / 2      // center y
        let bodyW: CGFloat  // body width
        let bodyH: CGFloat  // body height

        switch t.bodyShape {
        case .round:
            bodyW = s * 0.55; bodyH = s * 0.55
        case .oval:
            bodyW = s * 0.5;  bodyH = s * 0.6
        case .squarish:
            bodyW = s * 0.55; bodyH = s * 0.5
        case .blob:
            bodyW = s * 0.6;  bodyH = s * 0.55
        }

        let bodyRect = CGRect(x: cx - bodyW/2, y: cy - bodyH/2 - s*0.02, width: bodyW, height: bodyH)

        // 1. Body fill
        ctx.setFillColor(t.bodyColor.cgColor)
        switch t.bodyShape {
        case .round:
            ctx.fillEllipse(in: bodyRect)
        case .oval:
            ctx.fillEllipse(in: bodyRect)
        case .squarish:
            let path = CGPath(roundedRect: bodyRect, cornerWidth: bodyW * 0.25, cornerHeight: bodyH * 0.25, transform: nil)
            ctx.addPath(path)
            ctx.fillPath()
        case .blob:
            ctx.fillEllipse(in: bodyRect.insetBy(dx: -s*0.02, dy: s*0.02))
        }

        // 2. Accent belly patch
        let bellyRect = CGRect(x: cx - bodyW * 0.3, y: cy - bodyH * 0.25 - s*0.02, width: bodyW * 0.6, height: bodyH * 0.45)
        ctx.setFillColor(t.accentColor.cgColor)
        ctx.fillEllipse(in: bellyRect)

        // 3. Eyes
        let eyeY = cy + bodyH * 0.1
        let eyeSpacing = bodyW * 0.22
        let eyeSize: CGFloat

        switch t.eyeStyle {
        case .dot:
            eyeSize = s * 0.06
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: cx - eyeSpacing - eyeSize/2, y: eyeY - eyeSize/2, width: eyeSize, height: eyeSize))
            ctx.fillEllipse(in: CGRect(x: cx + eyeSpacing - eyeSize/2, y: eyeY - eyeSize/2, width: eyeSize, height: eyeSize))
        case .circle:
            eyeSize = s * 0.09
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: cx - eyeSpacing - eyeSize/2, y: eyeY - eyeSize/2, width: eyeSize, height: eyeSize))
            ctx.fillEllipse(in: CGRect(x: cx + eyeSpacing - eyeSize/2, y: eyeY - eyeSize/2, width: eyeSize, height: eyeSize))
            let pupil = eyeSize * 0.5
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: cx - eyeSpacing - pupil/2, y: eyeY - pupil/2, width: pupil, height: pupil))
            ctx.fillEllipse(in: CGRect(x: cx + eyeSpacing - pupil/2, y: eyeY - pupil/2, width: pupil, height: pupil))
        case .anime:
            eyeSize = s * 0.1
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: cx - eyeSpacing - eyeSize/2, y: eyeY - eyeSize*0.6, width: eyeSize, height: eyeSize * 1.2))
            ctx.fillEllipse(in: CGRect(x: cx + eyeSpacing - eyeSize/2, y: eyeY - eyeSize*0.6, width: eyeSize, height: eyeSize * 1.2))
            // Highlight
            let hl = eyeSize * 0.3
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: cx - eyeSpacing - eyeSize/2 + eyeSize*0.15, y: eyeY + eyeSize*0.15, width: hl, height: hl))
            ctx.fillEllipse(in: CGRect(x: cx + eyeSpacing - eyeSize/2 + eyeSize*0.15, y: eyeY + eyeSize*0.15, width: hl, height: hl))
        case .sleepy:
            eyeSize = s * 0.08
            ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
            ctx.setLineWidth(s * 0.02)
            // Left eye — horizontal arc
            ctx.addArc(center: CGPoint(x: cx - eyeSpacing, y: eyeY), radius: eyeSize/2, startAngle: .pi * 0.1, endAngle: .pi * 0.9, clockwise: false)
            ctx.strokePath()
            // Right eye
            ctx.addArc(center: CGPoint(x: cx + eyeSpacing, y: eyeY), radius: eyeSize/2, startAngle: .pi * 0.1, endAngle: .pi * 0.9, clockwise: false)
            ctx.strokePath()
        }

        // 4. Mouth
        let mouthY = cy - bodyH * 0.08
        ctx.setStrokeColor(CGColor(gray: 0.15, alpha: 1))
        ctx.setLineWidth(s * 0.018)

        switch t.mouthStyle {
        case .smile:
            ctx.addArc(center: CGPoint(x: cx, y: mouthY + s*0.02), radius: bodyW * 0.12, startAngle: .pi * 1.2, endAngle: .pi * 1.8, clockwise: false)
            ctx.strokePath()
        case .open:
            ctx.setFillColor(CGColor(gray: 0.15, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: cx - s*0.04, y: mouthY - s*0.03, width: s*0.08, height: s*0.06))
        case .catMouth:
            // W shape
            let mw = bodyW * 0.15
            ctx.move(to: CGPoint(x: cx - mw, y: mouthY))
            ctx.addLine(to: CGPoint(x: cx, y: mouthY - s*0.03))
            ctx.addLine(to: CGPoint(x: cx + mw, y: mouthY))
            ctx.strokePath()
        case .line:
            ctx.move(to: CGPoint(x: cx - bodyW * 0.1, y: mouthY))
            ctx.addLine(to: CGPoint(x: cx + bodyW * 0.1, y: mouthY))
            ctx.strokePath()
        }

        // 5. Ears / horns
        let earY = cy + bodyH/2 - s*0.02
        ctx.setFillColor(t.bodyColor.cgColor)

        switch t.earStyle {
        case .pointy:
            // Left ear
            ctx.move(to: CGPoint(x: cx - bodyW*0.3, y: earY))
            ctx.addLine(to: CGPoint(x: cx - bodyW*0.45, y: earY + s*0.2))
            ctx.addLine(to: CGPoint(x: cx - bodyW*0.15, y: earY + s*0.05))
            ctx.fillPath()
            // Right ear
            ctx.move(to: CGPoint(x: cx + bodyW*0.3, y: earY))
            ctx.addLine(to: CGPoint(x: cx + bodyW*0.45, y: earY + s*0.2))
            ctx.addLine(to: CGPoint(x: cx + bodyW*0.15, y: earY + s*0.05))
            ctx.fillPath()
            // Accent tips
            ctx.setFillColor(t.accentColor.cgColor)
            ctx.move(to: CGPoint(x: cx - bodyW*0.38, y: earY + s*0.13))
            ctx.addLine(to: CGPoint(x: cx - bodyW*0.45, y: earY + s*0.2))
            ctx.addLine(to: CGPoint(x: cx - bodyW*0.3, y: earY + s*0.15))
            ctx.fillPath()
            ctx.move(to: CGPoint(x: cx + bodyW*0.38, y: earY + s*0.13))
            ctx.addLine(to: CGPoint(x: cx + bodyW*0.45, y: earY + s*0.2))
            ctx.addLine(to: CGPoint(x: cx + bodyW*0.3, y: earY + s*0.15))
            ctx.fillPath()
        case .round:
            ctx.fillEllipse(in: CGRect(x: cx - bodyW*0.45, y: earY - s*0.02, width: s*0.14, height: s*0.16))
            ctx.fillEllipse(in: CGRect(x: cx + bodyW*0.45 - s*0.14, y: earY - s*0.02, width: s*0.14, height: s*0.16))
        case .antenna:
            ctx.setStrokeColor(t.bodyColor.cgColor)
            ctx.setLineWidth(s * 0.025)
            ctx.move(to: CGPoint(x: cx - bodyW*0.15, y: earY + s*0.02))
            ctx.addLine(to: CGPoint(x: cx - bodyW*0.2, y: earY + s*0.2))
            ctx.strokePath()
            ctx.move(to: CGPoint(x: cx + bodyW*0.15, y: earY + s*0.02))
            ctx.addLine(to: CGPoint(x: cx + bodyW*0.2, y: earY + s*0.2))
            ctx.strokePath()
            // Antenna tips
            ctx.setFillColor(t.accentColor.cgColor)
            ctx.fillEllipse(in: CGRect(x: cx - bodyW*0.2 - s*0.03, y: earY + s*0.17, width: s*0.06, height: s*0.06))
            ctx.fillEllipse(in: CGRect(x: cx + bodyW*0.2 - s*0.03, y: earY + s*0.17, width: s*0.06, height: s*0.06))
        case .none:
            break
        }

        // 6. Tail
        let tailX = cx + bodyW/2 - s*0.02
        let tailY = cy - bodyH * 0.1

        switch t.tailStyle {
        case .lightning:
            ctx.setFillColor(t.bodyColor.cgColor)
            ctx.move(to: CGPoint(x: tailX, y: tailY))
            ctx.addLine(to: CGPoint(x: tailX + s*0.15, y: tailY + s*0.08))
            ctx.addLine(to: CGPoint(x: tailX + s*0.1, y: tailY))
            ctx.addLine(to: CGPoint(x: tailX + s*0.22, y: tailY + s*0.12))
            ctx.addLine(to: CGPoint(x: tailX + s*0.12, y: tailY + s*0.04))
            ctx.addLine(to: CGPoint(x: tailX + s*0.08, y: tailY - s*0.04))
            ctx.fillPath()
        case .swirl:
            ctx.setStrokeColor(t.bodyColor.cgColor)
            ctx.setLineWidth(s * 0.03)
            ctx.addArc(center: CGPoint(x: tailX + s*0.1, y: tailY), radius: s*0.08, startAngle: .pi, endAngle: -.pi * 0.3, clockwise: true)
            ctx.strokePath()
        case .flame:
            ctx.setFillColor(NSColor(red: 1, green: 0.5, blue: 0.1, alpha: 1).cgColor)
            ctx.move(to: CGPoint(x: tailX, y: tailY - s*0.03))
            ctx.addLine(to: CGPoint(x: tailX + s*0.12, y: tailY + s*0.06))
            ctx.addLine(to: CGPoint(x: tailX + s*0.08, y: tailY - s*0.01))
            ctx.addLine(to: CGPoint(x: tailX + s*0.18, y: tailY + s*0.03))
            ctx.addLine(to: CGPoint(x: tailX + s*0.05, y: tailY - s*0.06))
            ctx.fillPath()
        case .none:
            break
        }

        // 7. Cheek marks
        let cheekY = cy - s*0.01
        switch t.cheekStyle {
        case .circles:
            ctx.setFillColor(NSColor(red: 1, green: 0.4, blue: 0.4, alpha: 0.5).cgColor)
            let cr = s * 0.055
            ctx.fillEllipse(in: CGRect(x: cx - bodyW*0.35, y: cheekY - cr, width: cr*2, height: cr*2))
            ctx.fillEllipse(in: CGRect(x: cx + bodyW*0.35 - cr*2, y: cheekY - cr, width: cr*2, height: cr*2))
        case .triangles:
            ctx.setFillColor(NSColor(red: 1, green: 0.4, blue: 0.4, alpha: 0.5).cgColor)
            let ts = s * 0.06
            // Left
            ctx.move(to: CGPoint(x: cx - bodyW*0.32, y: cheekY - ts*0.5))
            ctx.addLine(to: CGPoint(x: cx - bodyW*0.32 + ts, y: cheekY - ts*0.5))
            ctx.addLine(to: CGPoint(x: cx - bodyW*0.32 + ts*0.5, y: cheekY + ts*0.5))
            ctx.fillPath()
            // Right
            ctx.move(to: CGPoint(x: cx + bodyW*0.32, y: cheekY - ts*0.5))
            ctx.addLine(to: CGPoint(x: cx + bodyW*0.32 - ts, y: cheekY - ts*0.5))
            ctx.addLine(to: CGPoint(x: cx + bodyW*0.32 - ts*0.5, y: cheekY + ts*0.5))
            ctx.fillPath()
        case .none:
            break
        }

        let image = ctx.makeImage()

        // Store in cache before returning
        if let image = image {
            cache.setObject(CGImageBox(image), forKey: cacheKey)
        }
        return image
    }
}
