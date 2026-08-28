import SwiftUI

/// The edge-mounted rail silhouette from the reference design:
///
///  • the flush side is a dead-straight line on the screen edge
///  • at the top and bottom it **flares out** into that edge through a concave
///    (inverted-radius) fillet, bridging tab and edge into one continuous form
///  • the top and bottom edges are straight
///  • the inner side has convex rounded corners and a straight vertical edge
///
/// Every junction is tangent-continuous — each arc meets its neighbouring straight
/// run at exactly its tangent point — so there are no corners, steps, or joints.
/// Quarter arcs are exact circular arcs written as cubics via the circle constant.
struct EdgeTabShape: Shape {
    /// Radius of the concave flare where the tab meets the screen edge.
    var fillet: CGFloat = 22
    /// Radius of the convex rounding on the inner side.
    var corner: CGFloat = 20
    var flushRight: Bool = true

    /// Circle→cubic constant: 4/3·tan(π/8).
    private let k: CGFloat = 0.5522847498

    func path(in rect: CGRect) -> Path {
        let W = rect.width, H = rect.height
        let s = max(0, min(fillet, min(W, H / 2)))
        let r = max(0, min(corner, min(W - s, H / 2 - s)))

        var p = Path()

        // Top of the flush edge.
        p.move(to: CGPoint(x: W, y: 0))
        // Concave flare — leaves the edge vertically, arrives horizontally.
        p.addCurve(to: CGPoint(x: W - s, y: s),
                   control1: CGPoint(x: W, y: k * s),
                   control2: CGPoint(x: W - s + k * s, y: s))
        // Straight top edge.
        p.addLine(to: CGPoint(x: r, y: s))
        // Convex inner corner — horizontal into vertical.
        p.addCurve(to: CGPoint(x: 0, y: s + r),
                   control1: CGPoint(x: r - k * r, y: s),
                   control2: CGPoint(x: 0, y: s + r - k * r))
        // Straight inner edge.
        p.addLine(to: CGPoint(x: 0, y: H - s - r))
        // Convex inner corner — vertical into horizontal.
        p.addCurve(to: CGPoint(x: r, y: H - s),
                   control1: CGPoint(x: 0, y: H - s - r + k * r),
                   control2: CGPoint(x: r - k * r, y: H - s))
        // Straight bottom edge.
        p.addLine(to: CGPoint(x: W - s, y: H - s))
        // Concave flare back into the edge — horizontal into vertical.
        p.addCurve(to: CGPoint(x: W, y: H),
                   control1: CGPoint(x: W - s + k * s, y: H - s),
                   control2: CGPoint(x: W, y: H - k * s))
        // The flush edge closes the path.
        p.closeSubpath()

        if !flushRight {
            return p.applying(CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -W, y: 0))
        }
        return p
    }
}

/// The hover detail bubble from the reference: a rounded card with a speech-bubble
/// tail on the side facing the rail.
struct BubbleShape: Shape {
    var corner: CGFloat = 16
    var tailWidth: CGFloat = 13
    var tailHeight: CGFloat = 20
    /// True when the bubble sits to the left of the rail (tail points right).
    var tailOnRight: Bool = true

    func path(in rect: CGRect) -> Path {
        let bodyWidth = max(0, rect.width - tailWidth)
        let body = CGRect(x: tailOnRight ? rect.minX : rect.minX + tailWidth,
                          y: rect.minY, width: bodyWidth, height: rect.height)
        var p = Path(roundedRect: body, cornerRadius: corner, style: .continuous)

        let midY = rect.midY
        var tail = Path()
        if tailOnRight {
            tail.move(to: CGPoint(x: body.maxX - 2, y: midY - tailHeight / 2))
            tail.addLine(to: CGPoint(x: rect.maxX, y: midY))
            tail.addLine(to: CGPoint(x: body.maxX - 2, y: midY + tailHeight / 2))
        } else {
            tail.move(to: CGPoint(x: body.minX + 2, y: midY - tailHeight / 2))
            tail.addLine(to: CGPoint(x: rect.minX, y: midY))
            tail.addLine(to: CGPoint(x: body.minX + 2, y: midY + tailHeight / 2))
        }
        tail.closeSubpath()
        p.addPath(tail)
        return p
    }
}
