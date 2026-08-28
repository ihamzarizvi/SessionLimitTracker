import SwiftUI

/// The dark "Usage" bubble shown next to a ring on hover — the same layout as the
/// menu-bar popover, scoped to one provider.
struct ProviderDetailView: View {
    let status: ProviderStatus
    var colorblind: Bool = false
    /// True when the bubble sits left of the rail, so its tail points right.
    var tailOnRight: Bool = true

    private let tailW: CGFloat = 13

    @State private var now = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private let cardBG = Color(white: 0.08)
    private let textPrimary = Color.white
    private let textSecondary = Color(white: 0.62)
    private let track = Color(white: 0.20)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ProviderGlyph(id: status.id, size: 16, color: textPrimary)
                Text("\(status.name) Usage")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(textPrimary)
                Spacer()
                Text(status.source.badge)
                    .font(.system(size: 9))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(track, in: Capsule())
                    .foregroundStyle(textSecondary)
            }

            if status.session == nil && status.weekly == nil {
                Text(status.errorMessage ?? "No usage data yet")
                    .font(.callout).foregroundStyle(textSecondary)
            } else {
                if let s = status.session { bar(s) }
                if let w = status.weekly { bar(w) }
            }
        }
        .padding(16)
        .padding(tailOnRight ? .trailing : .leading, tailW)
        .frame(width: 280 + tailW)
        .background(
            BubbleShape(corner: 16, tailWidth: tailW, tailOnRight: tailOnRight).fill(cardBG)
        )
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        .onReceive(tick) { now = $0 }
    }

    private func bar(_ window: UsageWindow) -> some View {
        let accent = ThresholdColor.color(for: window.fraction, colorblind: colorblind)
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(window.label).font(.system(size: 13)).foregroundStyle(textPrimary)
                Spacer()
                Text(Formatting.reset(window.resetsAt, now: now))
                    .font(.system(size: 11)).foregroundStyle(textSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(track)
                    Capsule().fill(accent)
                        .frame(width: max(4, geo.size.width * window.fraction))
                }
            }
            .frame(height: 5)
            Text("\(window.percentText) Used").font(.system(size: 11)).foregroundStyle(textSecondary)
        }
    }
}
