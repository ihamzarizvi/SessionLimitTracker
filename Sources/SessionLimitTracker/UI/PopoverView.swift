import SwiftUI

/// The menu-bar dropdown — the dark "Claude Usage" speech bubble from the mockup:
/// a header, Claude's session and weekly bars (label above, "% Used" below), and a
/// subtle footer. Always dark, matching the reference.
struct PopoverView: View {
    @ObservedObject var appState: AppState
    @State private var now = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // Fixed dark palette to match the mockup regardless of system theme.
    private let cardBG = Color(white: 0.07)
    private let textPrimary = Color.white
    private let textSecondary = Color(white: 0.62)
    private let track = Color(white: 0.20)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if let claude = appState.claude {
                if let session = claude.session {
                    bar(session)
                }
                if let weekly = claude.weekly {
                    bar(weekly)
                }
                if claude.session == nil && claude.weekly == nil {
                    Text(claude.errorMessage ?? "No usage data yet")
                        .font(.callout)
                        .foregroundStyle(textSecondary)
                }
            }

            footer
        }
        .padding(18)
        .frame(width: 330)
        .background(cardBG)
        .onReceive(tick) { now = $0 }
    }

    private var header: some View {
        HStack(spacing: 9) {
            ProviderGlyph(id: .claude, size: 18, color: textPrimary)
            Text("Claude Usage")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(textPrimary)
            Spacer()
            Button {
                Task { await appState.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(textSecondary)
            }
            .buttonStyle(.plain)
            .help("Refresh now")
        }
    }

    /// One labeled bar: title (left) + reset (right) above the bar, "% Used" below.
    private func bar(_ window: UsageWindow) -> some View {
        let accent = ThresholdColor.color(for: window.fraction, colorblind: appState.colorblind)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(window.label)
                    .font(.system(size: 14))
                    .foregroundStyle(textPrimary)
                Spacer()
                Text(Formatting.reset(window.resetsAt, now: now))
                    .font(.system(size: 12))
                    .foregroundStyle(textSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(track)
                    Capsule().fill(accent)
                        .frame(width: max(4, geo.size.width * window.fraction))
                        .animation(.easeInOut(duration: 0.4), value: window.fraction)
                }
            }
            .frame(height: 5)
            Text("\(window.percentText) Used")
                .font(.system(size: 12))
                .foregroundStyle(textSecondary)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let src = appState.claude?.source {
                Text(src.badge)
                    .font(.system(size: 10))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(track, in: Capsule())
                    .foregroundStyle(textSecondary)
            }
            Spacer()
            Button("Settings") { SettingsWindow.show(appState: appState) }
                .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(textSecondary)
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(textSecondary)
        }
    }
}
