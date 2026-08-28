import AppKit
import SwiftUI
import Combine

/// App entry. A menu-bar accessory (no Dock icon) that owns the status item, the
/// popover, and the notch rail window.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var notch: NotchWindow!
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()

        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .darkAqua)   // dark bubble like the mockup
        popover.contentViewController = NSHostingController(rootView: PopoverView(appState: appState))

        notch = NotchWindow(appState: appState)
        notch.show()

        // Keep the menu-bar title in sync with Claude's session percentage.
        appState.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                self?.updateStatusTitle(from: snapshot)
            }
            .store(in: &cancellables)

        appState.start()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "Claude usage")
            button.imagePosition = .imageLeading
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
    }

    private func updateStatusTitle(from snapshot: UsageSnapshot) {
        guard appState.menuBarShowPercent,
              let claude = snapshot.status(for: .claude),
              let window = claude.primaryWindow else {
            statusItem.button?.title = ""
            return
        }
        statusItem.button?.title = " \(window.percentText)"
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

let delegate = AppDelegate()
let application = NSApplication.shared
application.delegate = delegate
application.run()
