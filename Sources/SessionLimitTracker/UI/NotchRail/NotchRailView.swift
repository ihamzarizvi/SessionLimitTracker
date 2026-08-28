import SwiftUI
import Combine

/// Shared hover state between the SwiftUI rail and the AppKit panels.
@MainActor
final class RailController: ObservableObject {
    @Published var isHovering = false
    /// Which provider ring the pointer is over (drives the detail popover).
    @Published var hoveredProvider: ProviderID?
}

/// Fixed layout metrics so the AppKit side can position the detail popover exactly
/// against a given ring. All values are in points before the rail scale is applied.
enum RailMetrics {
    /// Concave flare where the rail meets the screen edge.
    static let fillet: CGFloat = 22
    /// Convex rounding on the inner side.
    static let corner: CGFloat = 20
    /// Vertical padding that keeps content clear of the flares.
    static let vPad: CGFloat = 34
    static let hPad: CGFloat = 14
    static let ringDiameter: CGFloat = 46
    static let internalGap: CGFloat = ringDiameter * 0.16
    static let labelHeight: CGFloat = 18          // % text line
    static var ringBlock: CGFloat { ringDiameter + internalGap + labelHeight }
    static let vSpacing: CGFloat = 18
    static var width: CGFloat { ringDiameter + hPad * 2 }

    /// Extra breathing room above and below the provider group, as a fraction of
    /// the rail's total height (applied to each side).
    static let groupPadFraction: CGFloat = 0.02

    /// Height of the ring stack itself.
    static func ringsHeight(_ count: Int) -> CGFloat {
        CGFloat(count) * ringBlock + CGFloat(max(0, count - 1)) * vSpacing
    }
    /// Solves H = 2·vPad + 2·(f·H) + rings  ->  H = (2·vPad + rings) / (1 - 2f),
    /// so the group padding really is `groupPadFraction` of the final height.
    static func contentHeight(_ count: Int) -> CGFloat {
        (vPad * 2 + ringsHeight(count)) / (1 - 2 * groupPadFraction)
    }
    /// The 2% padding in points for a given provider count.
    static func groupPad(_ count: Int) -> CGFloat {
        groupPadFraction * contentHeight(count)
    }
    /// Distance from the top of the rail to the vertical center of ring `i`.
    static func ringCenterFromTop(_ i: Int, count: Int) -> CGFloat {
        vPad + groupPad(count) + CGFloat(i) * (ringBlock + vSpacing) + ringDiameter / 2
    }
}

/// The vertical stack of provider rings (an always-dark rounded bar). Collapses to
/// a thin edge tab when autohide is on, expanding on hover.
struct NotchRailView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var controller: RailController

    private var scale: CGFloat { CGFloat(appState.railScale) }
    private var expanded: Bool { !appState.railAutoHide || controller.isHovering }

    var body: some View {
        Group {
            if expanded { expandedRail } else { collapsedPill }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { controller.isHovering = hovering }
            if !hovering { controller.hoveredProvider = nil }
        }
    }

    private var providerCount: Int { max(1, appState.enabledProviders.count) }

    private var expandedRail: some View {
        VStack(spacing: RailMetrics.vSpacing * scale) {
            ForEach(appState.visibleStatuses) { status in
                RingView(status: status, colorblind: appState.colorblind,
                         diameter: RailMetrics.ringDiameter * scale, lineWidth: 4 * scale,
                         onDark: true,
                         onHover: { hovering in
                             controller.hoveredProvider = hovering ? status.id
                                 : (controller.hoveredProvider == status.id ? nil : controller.hoveredProvider)
                         })
            }
        }
        .padding(.vertical, (RailMetrics.vPad + RailMetrics.groupPad(providerCount)) * scale)
        .padding(.horizontal, RailMetrics.hPad * scale)
        .frame(maxWidth: .infinity)
        .background(
            EdgeTabShape(fillet: RailMetrics.fillet * scale,
                         corner: RailMetrics.corner * scale,
                         flushRight: appState.railEdge == .right)
                .fill(Color.black)
        )
    }

    /// A thin vertical tab flush to the edge (collapsed / autohidden state).
    private var collapsedPill: some View {
        RoundedRectangle(cornerRadius: 8 * scale, style: .continuous)
            .fill(Color.black)
            .overlay(
                Capsule()
                    .fill(ThresholdColor.color(for: maxFraction, colorblind: appState.colorblind))
                    .frame(width: 4 * scale, height: 26 * scale)
            )
            .frame(width: 16 * scale, height: 56 * scale)
    }

    private var maxFraction: Double {
        appState.visibleStatuses.compactMap { $0.primaryWindow?.fraction }.max() ?? 0
    }
}
