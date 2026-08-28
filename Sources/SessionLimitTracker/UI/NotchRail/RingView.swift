import SwiftUI

/// A provider ring styled like the mockup: a filled dark disc with the progress
/// arc hugging its edge, a white glyph centered, and the percentage beneath.
struct RingView: View {
    let status: ProviderStatus
    var colorblind: Bool = false
    var diameter: CGFloat = 46
    var lineWidth: CGFloat = 4
    /// When true, render light-on-black (the always-dark notch rail in the mockup).
    var onDark: Bool = false
    /// Called when the pointer enters/leaves this ring (drives the detail popover).
    var onHover: ((Bool) -> Void)? = nil

    private var window: UsageWindow? { status.primaryWindow }
    private var fraction: Double { window?.fraction ?? 0 }
    private var accent: Color { ThresholdColor.color(for: fraction, colorblind: colorblind) }
    private var glyphColor: Color { onDark ? .white : Theme.textPrimary }
    // Visible grey border ring + darker disc, matching the mockup.
    private var trackColor: Color { onDark ? Color(white: 0.30) : Color.black.opacity(0.14) }
    private var discColor: Color { onDark ? Color(white: 0.13) : Color(white: 0.92) }

    var body: some View {
        VStack(spacing: diameter * 0.16) {
            ZStack {
                Circle().fill(discColor).padding(lineWidth)
                Circle().stroke(trackColor, lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.4), value: fraction)
                ProviderGlyph(id: status.id, size: diameter * 0.5, color: glyphColor)
            }
            .frame(width: diameter, height: diameter)

            Text(window?.percentText ?? "—")
                .font(.system(size: diameter * 0.32, weight: .semibold, design: .rounded))
                .foregroundStyle(glyphColor)
        }
        .contentShape(Rectangle())
        .onHover { onHover?($0) }
    }
}
