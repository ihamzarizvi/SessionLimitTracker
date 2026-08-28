import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        TabView {
            GeneralTab(appState: appState).tabItem { Label("General", systemImage: "gearshape") }
            ProvidersTab(appState: appState).tabItem { Label("Providers", systemImage: "point.3.connected.trianglepath.dotted") }
            AppearanceTab(appState: appState).tabItem { Label("Appearance", systemImage: "paintpalette") }
            AlertsTab(appState: appState).tabItem { Label("Alerts", systemImage: "bell") }
            AboutTab().tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(minWidth: 480, minHeight: 400)
        .preferredColorScheme(appState.appearance.colorScheme)
    }
}

private struct GeneralTab: View {
    @ObservedObject var appState: AppState
    var body: some View {
        Form {
            Toggle("Launch at login", isOn: $appState.launchAtLogin)
            Toggle("Show percentage in the menu bar", isOn: $appState.menuBarShowPercent)
            HStack {
                Text("Refresh every")
                Stepper("\(Int(appState.pollInterval))s",
                        value: $appState.pollInterval, in: 10...600, step: 10)
            }
            Text("The authoritative account link polls no faster than every 180s regardless of this setting.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct AppearanceTab: View {
    @ObservedObject var appState: AppState
    var body: some View {
        Form {
            Section("Theme") {
                Picker("Appearance", selection: $appState.appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Colorblind-safe palette", isOn: $appState.colorblind)
            }
            Section("Edge rail") {
                Toggle("Show the rail", isOn: $appState.railVisible)
                Toggle("Auto-hide (expand on hover)", isOn: $appState.railAutoHide)
                    .disabled(!appState.railVisible)
                Picker("Side", selection: $appState.railEdge) {
                    ForEach(RailEdge.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(!appState.railVisible)
                HStack {
                    Text("Size")
                    Slider(value: $appState.railScale, in: 0.7...1.6)
                    Text("\(Int(appState.railScale * 100))%").monospacedDigit()
                }
                .disabled(!appState.railVisible)
                HStack {
                    Text("Drag the rail up or down; it snaps to the nearest edge.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset position") { appState.resetRailPosition() }
                        .disabled(!appState.railVisible)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ProvidersTab: View {
    @ObservedObject var appState: AppState
    @State private var connecting: ProviderID?

    var body: some View {
        Form {
            Section {
                ForEach(ProviderID.allCases, id: \.self) { id in
                    let shown = appState.enabledProviders.contains(id)
                    HStack(spacing: 10) {
                        Toggle(isOn: Binding(
                            get: { shown },
                            set: { on in
                                if on { appState.enabledProviders.insert(id) } else { appState.enabledProviders.remove(id) }
                            }
                        )) {
                            Label {
                                Text(id.displayName)
                            } icon: {
                                Image(systemName: shown ? "eye" : "eye.slash")
                                    .foregroundStyle(shown ? .primary : .secondary)
                            }
                        }
                        .toggleStyle(.switch)

                        Spacer()

                        let c = appState.connections.connection(for: id)
                        Image(systemName: c.state.symbol).foregroundStyle(color(for: c.state))
                        Text(c.method == .none ? "Local estimate" : c.method.label)
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Connect…") { connecting = id }
                    }
                }
            } header: {
                Text("Watchlist — shown in the dock")
            } footer: {
                Text("Toggle a provider to add or remove its ring from the sidebar dock. “Connect…” links the account for real numbers; Claude also works as a no-login local estimate.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .sheet(item: $connecting) { id in
            ConnectSheetView(providerID: id, connections: appState.connections) {
                connecting = nil
                Task { await appState.refresh() }
            }
        }
    }

    private func color(for state: ConnectionState) -> Color {
        switch state {
        case .connected: return .green
        case .needsAuth: return .yellow
        case .error: return .red
        case .notConnected: return .secondary
        }
    }
}

private struct AlertsTab: View {
    @ObservedObject var appState: AppState
    private let presets = [50, 75, 90, 100]

    var body: some View {
        Form {
            Toggle("Enable usage alerts", isOn: $appState.alertsEnabled)
            Section("Notify at") {
                ForEach(presets, id: \.self) { level in
                    Toggle("\(level)%", isOn: Binding(
                        get: { appState.alertThresholds.contains(level) },
                        set: { on in
                            var s = Set(appState.alertThresholds)
                            if on { s.insert(level) } else { s.remove(level) }
                            appState.alertThresholds = s.sorted()
                        }
                    ))
                }
            }
            Section("Quiet hours") {
                Toggle("Silence alerts during quiet hours", isOn: $appState.quietHoursEnabled)
                Stepper("From \(appState.quietStartHour):00", value: $appState.quietStartHour, in: 0...23)
                Stepper("To \(appState.quietEndHour):00", value: $appState.quietEndHour, in: 0...23)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AboutTab: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppInfo.name).font(.title3).bold()
                    Text("Version \(AppInfo.version)")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(AppInfo.tagline)
                        .font(.callout).foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Developer").font(.headline)
                    Text(Developer.fullName).font(.callout)
                    Text(Developer.role)
                        .font(.caption).foregroundStyle(.secondary)
                    Text(Developer.location)
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 14) {
                        Link("hamzarizvi.com", destination: Developer.website)
                        Link("GitHub", destination: Developer.github)
                        Link("LinkedIn", destination: Developer.linkedin)
                        Link("Email", destination: URL(string: "mailto:\(Developer.email)")!)
                    }
                    .font(.callout)
                    Link("Source code", destination: AppInfo.repository)
                        .font(.callout)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Privacy").font(.headline)
                    Text("Claude numbers are estimated locally from ~/.claude transcript files — this machine only, no login. Authoritative account linking is opt-in and consent-gated. Credentials live only in the macOS Keychain and are never logged or sent off-device.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Text(Developer.copyright)
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Lightweight standalone Settings window (SwiftPM has no Settings scene).
@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show(appState: AppState) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = NSHostingController(rootView: SettingsView(appState: appState))
        controller.preferredContentSize = NSSize(width: 480, height: 400)
        let w = NSWindow(contentViewController: controller)
        w.title = "Settings"
        w.styleMask = [.titled, .closable, .miniaturizable]
        w.setContentSize(NSSize(width: 480, height: 400))
        w.center()
        w.isReleasedWhenClosed = false
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
