import SwiftUI

/// Brand-style provider glyphs drawn as vector shapes (no bundled assets):
/// Claude sunburst, OpenAI blossom/knot, Gemini 4-point spark.
struct ProviderGlyph: View {
    let id: ProviderID
    var size: CGFloat
    var color: Color

    var body: some View {
        Group {
            switch id {
            case .claude:
                ClaudeBurst()
                    .stroke(color, style: StrokeStyle(lineWidth: size * 0.085, lineCap: .round))
            case .openai:
                OpenAIKnot()
                    .stroke(color, style: StrokeStyle(lineWidth: size * 0.075, lineCap: .round, lineJoin: .round))
            case .gemini:
                GeminiSpark().fill(color)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Claude: a radial sunburst of rounded spokes.
struct ClaudeBurst: Shape {
    var rays = 12
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let inner = rect.width * 0.06
        let outer = rect.width * 0.46
        for i in 0..<rays {
            let a = Double(i) / Double(rays) * 2 * .pi
            let dx = CGFloat(cos(a)), dy = CGFloat(sin(a))
            p.move(to: CGPoint(x: c.x + dx * inner, y: c.y + dy * inner))
            p.addLine(to: CGPoint(x: c.x + dx * outer, y: c.y + dy * outer))
        }
        return p
    }
}

/// OpenAI: a six-petal blossom/knot (rotationally symmetric loops).
struct OpenAIKnot: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let R = rect.width * 0.42
        let bulge = rect.width * 0.17
        for i in 0..<6 {
            let a = Double(i) / 6 * 2 * .pi - .pi / 2
            let dx = CGFloat(cos(a)), dy = CGFloat(sin(a))
            let px = CGFloat(-sin(a)), py = CGFloat(cos(a))
            let inner = CGPoint(x: c.x + dx * R * 0.18, y: c.y + dy * R * 0.18)
            let outer = CGPoint(x: c.x + dx * R, y: c.y + dy * R)
            let mid = CGPoint(x: (inner.x + outer.x) / 2, y: (inner.y + outer.y) / 2)
            p.move(to: inner)
            p.addQuadCurve(to: outer, control: CGPoint(x: mid.x + px * bulge, y: mid.y + py * bulge))
            p.addQuadCurve(to: inner, control: CGPoint(x: mid.x - px * bulge, y: mid.y - py * bulge))
        }
        return p
    }
}

/// Gemini: a four-point spark with concave sides.
struct GeminiSpark: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = rect.width * 0.5
        let k = r * 0.14   // concavity: smaller = sharper waist
        let top = CGPoint(x: c.x, y: c.y - r)
        let right = CGPoint(x: c.x + r, y: c.y)
        let bottom = CGPoint(x: c.x, y: c.y + r)
        let left = CGPoint(x: c.x - r, y: c.y)
        p.move(to: top)
        p.addQuadCurve(to: right, control: CGPoint(x: c.x + k, y: c.y - k))
        p.addQuadCurve(to: bottom, control: CGPoint(x: c.x + k, y: c.y + k))
        p.addQuadCurve(to: left, control: CGPoint(x: c.x - k, y: c.y + k))
        p.addQuadCurve(to: top, control: CGPoint(x: c.x - k, y: c.y - k))
        p.closeSubpath()
        return p
    }
}
