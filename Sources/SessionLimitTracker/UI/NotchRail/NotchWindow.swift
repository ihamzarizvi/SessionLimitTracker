import AppKit
import SwiftUI
import Combine

/// A borderless, always-on-top panel docked to the left or right screen edge — a
/// Samsung-style edge panel. Draggable vertically (snaps back to the nearest edge),
/// and shows a per-provider detail bubble next to a ring on hover.
@MainActor
final class NotchWindow {
    private let panel: NSPanel
    private let detailPanel: NSPanel
    private let appState: AppState
    private let controller = RailController()
    private var cancellables = Set<AnyCancellable>()
    private var isProgrammaticMove = false
    private var snapWork: DispatchWorkItem?

    private let edgeMargin: CGFloat = 0   // flush against the screen edge

    init(appState: AppState) {
        self.appState = appState

        panel = NotchWindow.makePanel(size: NSSize(width: 74, height: 220))
        panel.isMovableByWindowBackground = true
        let host = NSHostingView(rootView: NotchRailView(appState: appState, controller: controller))
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        detailPanel = NotchWindow.makePanel(size: NSSize(width: 280, height: 160))
        detailPanel.hasShadow = false

        NotificationCenter.default.publisher(for: NSWindow.didMoveNotification, object: panel)
            .sink { [weak self] _ in self?.scheduleSnap() }
            .store(in: &cancellables)

        controller.$isHovering
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.layout() }
            .store(in: &cancellables)

        controller.$hoveredProvider
            .receive(on: RunLoop.main)
            .sink { [weak self] id in self?.updateDetail(for: id) }
            .store(in: &cancellables)

        let settingsChanges: [AnyPublisher<Void, Never>] = [
            appState.$railVisible.map { _ in () }.eraseToAnyPublisher(),
            appState.$railAutoHide.map { _ in () }.eraseToAnyPublisher(),
            appState.$railScale.map { _ in () }.eraseToAnyPublisher(),
            appState.$railEdge.map { _ in () }.eraseToAnyPublisher(),
            appState.$railLayoutTick.map { _ in () }.eraseToAnyPublisher(),
            appState.$enabledProviders.map { _ in () }.eraseToAnyPublisher()
        ]
        Publishers.MergeMany(settingsChanges)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.layout() }
            .store(in: &cancellables)
    }

    private static func makePanel(size: NSSize) -> NSPanel {
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .statusBar
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return p
    }

    func show() { layout() }
    func hide() { panel.orderOut(nil); detailPanel.orderOut(nil) }

    // MARK: - Drag → snap to edge

    private func scheduleSnap() {
        guard !isProgrammaticMove else { return }
        snapWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.snapToEdge() }
        snapWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func snapToEdge() {
        guard let screen = NSScreen.main else { return }
        let f = panel.frame
        appState.railEdge = f.midX < screen.frame.midX ? .left : .right
        appState.setRailVerticalOffset(max(0, Double(screen.frame.maxY - f.maxY)))
        layout()
    }

    // MARK: - Rail layout

    private func layout() {
        guard appState.railVisible else { panel.orderOut(nil); detailPanel.orderOut(nil); return }

        let scale = CGFloat(appState.railScale)
        let expanded = !appState.railAutoHide || controller.isHovering
        let count = max(1, appState.enabledProviders.count)

        let size: CGSize = expanded
            ? CGSize(width: RailMetrics.width * scale, height: RailMetrics.contentHeight(count) * scale)
            : CGSize(width: 22 * scale, height: 60 * scale)

        let origin = clampVertically(edgeOrigin(for: size), size: size)
        isProgrammaticMove = true
        panel.setFrame(NSRect(origin: origin, size: size), display: true, animate: false)
        DispatchQueue.main.async { [weak self] in self?.isProgrammaticMove = false }
        panel.orderFrontRegardless()

        if !expanded { detailPanel.orderOut(nil) }
    }

    private func edgeOrigin(for size: CGSize) -> NSPoint {
        guard let screen = NSScreen.main else { return .zero }
        let frame = screen.frame
        let x: CGFloat = appState.railEdge == .left
            ? frame.minX + edgeMargin
            : frame.maxX - size.width - edgeMargin
        let topY = frame.maxY - CGFloat(appState.railVerticalOffset)
        return NSPoint(x: x, y: topY - size.height)
    }

    private func clampVertically(_ p: NSPoint, size: CGSize) -> NSPoint {
        guard let screen = NSScreen.main else { return p }
        let f = screen.frame
        return NSPoint(x: p.x, y: min(max(p.y, f.minY), f.maxY - size.height))
    }

    // MARK: - Detail bubble

    private func updateDetail(for id: ProviderID?) {
        guard let id,
              appState.railVisible,
              (!appState.railAutoHide || controller.isHovering),
              let index = appState.visibleStatuses.firstIndex(where: { $0.id == id }),
              let status = appState.snapshot.status(for: id) else {
            detailPanel.orderOut(nil)
            return
        }

        let host = NSHostingController(rootView: ProviderDetailView(status: status, colorblind: appState.colorblind,
                                                              tailOnRight: appState.railEdge == .right))
        detailPanel.contentViewController = host
        host.view.layoutSubtreeIfNeeded()
        var size = host.view.fittingSize
        if size.width < 10 || size.height < 10 { size = NSSize(width: 280, height: 150) }
        detailPanel.setContentSize(size)

        detailPanel.setFrameOrigin(detailOrigin(ringIndex: index, size: size))
        detailPanel.orderFrontRegardless()
    }

    /// Position the bubble beside the rail, vertically centered on the hovered ring.
    private func detailOrigin(ringIndex: Int, size: NSSize) -> NSPoint {
        guard let screen = NSScreen.main else { return .zero }
        let railFrame = panel.frame
        let scale = CGFloat(appState.railScale)
        let centerFromTop = RailMetrics.ringCenterFromTop(ringIndex, count: max(1, appState.enabledProviders.count)) * scale
        let ringCenterY = railFrame.maxY - centerFromTop

        let gap: CGFloat = 0   // the bubble tail meets the rail
        var x = appState.railEdge == .right
            ? railFrame.minX - size.width - gap   // bubble to the left of a right-edge rail
            : railFrame.maxX + gap                // bubble to the right of a left-edge rail
        var y = ringCenterY - size.height / 2

        // Keep on-screen.
        let f = screen.frame
        x = min(max(x, f.minX + 4), f.maxX - size.width - 4)
        y = min(max(y, f.minY + 4), f.maxY - size.height - 4)
        return NSPoint(x: x, y: y)
    }
}
