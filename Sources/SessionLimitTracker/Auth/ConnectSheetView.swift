import SwiftUI

/// Per-provider connection wizard (OmniRoute-style): pick a provider + method,
/// run OAuth / enter a credential, then reload the saved connection and run a
/// connection test — showing pass/fail before returning.
struct ConnectSheetView: View {
    @ObservedObject var connections: ConnectionStore
    var onClose: () -> Void

    @State private var providerID: ProviderID
    @State private var stage: Stage = .configure

    @State private var method: ConnectionMethod = .none
    @State private var secret: String = ""
    @State private var manualSession: Double = 0
    @State private var manualWeekly: Double = 0
    @State private var showConsent = false

    // OAuth
    @State private var oauthConfig = OAuthConfig(clientID: "", authorizeURL: "", tokenURL: "", scopes: "", redirectURI: "", callbackScheme: "")
    @State private var isSigningIn = false
    @State private var signInError: String?
    @State private var flow = OAuthLoginFlow()
    @State private var consentThenSignIn = false
    @State private var useSystemBrowser = true

    // Test
    @State private var testResult: ConnectionTestResult?
    @State private var helperMessage: String?

    enum Stage { case configure, testing, result }

    init(providerID: ProviderID, connections: ConnectionStore, onClose: @escaping () -> Void) {
        _connections = ObservedObject(wrappedValue: connections)
        self.onClose = onClose
        _providerID = State(initialValue: providerID)
        // Start on a valid method so the Picker always has a matching tag
        // (loadCurrent refines it on appear).
        _method = State(initialValue: Self.methods(for: providerID).first ?? .manual)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch stage {
            case .configure: configureStage
            case .testing: testingStage
            case .result: resultStage
            }
        }
        .padding(20)
        .frame(width: 500, height: 460)
        .onAppear(perform: loadCurrent)
        .onChange(of: providerID) { _, _ in loadCurrent() }
        .sheet(isPresented: $showConsent) {
            OAuthConsentView(
                onAccept: {
                    showConsent = false
                    if consentThenSignIn { consentThenSignIn = false; performSignIn() } else { commit() }
                },
                onCancel: { showConsent = false; consentThenSignIn = false }
            )
        }
    }

    // MARK: - Configure stage

    private var configureStage: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Connect \(providerID.displayName)").font(.title3).bold()
                Spacer()
                Picker("", selection: $providerID) {
                    ForEach(ProviderID.allCases) { Text($0.displayName).tag($0) }
                }
                .labelsHidden().frame(width: 130)
                .help("Change provider")
            }

            Picker("Method", selection: $method) {
                ForEach(methods, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.menu)

            ScrollView { methodDetail.frame(maxWidth: .infinity, alignment: .leading) }
                .frame(maxHeight: .infinity)

            if let err = signInError { Text(err).font(.caption).foregroundStyle(.red) }

            HStack {
                if connections.connection(for: providerID).state == .connected {
                    Button("Disconnect", role: .destructive) {
                        connections.disconnect(providerID); onClose()
                    }
                }
                Spacer()
                Button("Cancel", role: .cancel, action: onClose)
                Button("Save & test") { attemptSave() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
    }

    private var methods: [ConnectionMethod] { Self.methods(for: providerID) }

    static func methods(for id: ProviderID) -> [ConnectionMethod] {
        switch id {
        case .claude: return [.detectClaudeCode, .oauth, .sessionToken, .apiKey, .manual]
        case .openai: return [.detectCodex, .oauth, .apiKey, .sessionToken, .manual]
        case .gemini: return [.oauth, .apiKey, .manual]
        }
    }

    @ViewBuilder private var methodDetail: some View {
        switch method {
        case .detectClaudeCode:
            let found = ClaudeCredentials.looksConnected()
            Label(found ? "Claude Code detected." : "Claude Code not found — sign in with `claude` first.",
                  systemImage: found ? "checkmark.circle" : "questionmark.circle")
                .foregroundStyle(found ? .green : .secondary)
            Text("Connect Claude Code with its existing OAuth login. Reads your token live to fetch real shared-pool numbers. Subject to the policy note.")
                .font(.caption).foregroundStyle(.secondary)
            Label {
                Text("macOS will ask once per launch to read Claude Code's Keychain item — click **Always Allow**. (Unsigned dev builds re-ask each build.)")
            } icon: { Image(systemName: "key.fill") }
                .font(.caption2).foregroundStyle(.secondary)
            Button("Prefer no prompts? Use a pasted token instead") {
                TerminalHelper.openTerminalWithCommandOnClipboard("claude setup-token")
                helperMessage = "Command copied. In Terminal press ⌘V ↩, then paste the printed token below."
                method = .sessionToken
            }
            .font(.caption)
            if let helperMessage { Text(helperMessage).font(.caption2).foregroundStyle(.blue) }

        case .detectCodex:
            let found = CodexCLI.isInstalled()
            Label(found ? "Codex CLI detected." : "Codex CLI not found — install it and run `codex login`.",
                  systemImage: found ? "checkmark.circle" : "questionmark.circle")
                .foregroundStyle(found ? .green : .secondary)
            Text("Uses your existing “Sign in with ChatGPT” session in Codex. Reads the real ChatGPT rate limits Codex caches locally — no extra requests. Run a Codex session once so limits are populated.")
                .font(.caption).foregroundStyle(.secondary)

        case .oauth:
            oauthDetail

        case .apiKey:
            SecureField("API key", text: $secret).textFieldStyle(.roundedBorder)
            Text("Stored in the macOS Keychain. Used for the provider's usage/cost API (API spend, not consumer caps).")
                .font(.caption).foregroundStyle(.secondary)

        case .sessionToken:
            SecureField("Session token", text: $secret).textFieldStyle(.roundedBorder)
            Text("Stored in this app's own Keychain vault (no cross-app prompt when read).")
                .font(.caption).foregroundStyle(.secondary)
            if providerID == .claude {
                Button("Generate one with `claude setup-token`") {
                    TerminalHelper.openTerminalWithCommandOnClipboard("claude setup-token")
                    helperMessage = "Command copied. In Terminal press ⌘V ↩, then paste the printed token above."
                }
                .font(.caption)
                Text("Or paste a browser session token from DevTools → Application → Cookies. Tokens expire periodically. Subject to the policy note.")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("Copy from your browser's DevTools → Application → Cookies. Expires periodically.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if let helperMessage { Text(helperMessage).font(.caption2).foregroundStyle(.blue) }

        case .manual:
            VStack(alignment: .leading) {
                Text("Session used: \(Int(manualSession))%")
                Slider(value: $manualSession, in: 0...100)
                Text("Weekly used: \(Int(manualWeekly))%")
                Slider(value: $manualWeekly, in: 0...100)
            }

        case ConnectionMethod.none:
            Text("Select a connection method.").foregroundStyle(.secondary)
        }
    }

    private var oauthDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Register your own OAuth app with \(providerID.displayName) and paste its Client ID. We use Authorization Code + PKCE; the token is stored only in the Keychain.")
                .font(.caption).foregroundStyle(.secondary)
            field("Client ID", $oauthConfig.clientID)
            Toggle("Sign in with my default browser (uses your logged-in session)", isOn: $useSystemBrowser)
                .font(.callout)
            Text(useSystemBrowser
                 ? "Opens your default browser and catches the redirect on http://127.0.0.1:<port>/callback — add that loopback URL to your OAuth app's allowed redirects."
                 : "Uses an in-app secure web view that shares your Safari login; set the redirect URI below to match your OAuth app.")
                .font(.caption2).foregroundStyle(.secondary)
            DisclosureGroup("Advanced (endpoints & scopes)") {
                field("Authorize URL", $oauthConfig.authorizeURL)
                field("Token URL", $oauthConfig.tokenURL)
                field("Scopes", $oauthConfig.scopes)
                field("Redirect URI (in-app view)", $oauthConfig.redirectURI)
                field("Callback scheme (in-app view)", $oauthConfig.callbackScheme)
            }
            Button {
                signIn()
            } label: {
                if isSigningIn { ProgressView().controlSize(.small) } else { Text("Start OAuth flow") }
            }
            .disabled(oauthConfig.clientID.trimmingCharacters(in: .whitespaces).isEmpty || isSigningIn)
            if providerID != .claude {
                Text("Signs you in; usage numbers still require a usage endpoint the provider exposes.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func field(_ label: String, _ binding: Binding<String>) -> some View {
        HStack {
            Text(label).font(.caption).frame(width: 150, alignment: .leading).foregroundStyle(.secondary)
            TextField(label, text: binding).textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Testing / result stages

    private var testingStage: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
            Text("Running connection test for \(providerID.displayName)…")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var resultStage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            Label {
                Text(testResult?.ok == true ? "Connected" : "Connection test failed")
                    .font(.title3).bold()
            } icon: {
                Image(systemName: testResult?.ok == true ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .foregroundStyle(testResult?.ok == true ? .green : .red)
            }
            Text(testResult?.message ?? "")
                .foregroundStyle(.secondary)
            Spacer()
            HStack {
                Button("Reconfigure") { stage = .configure }
                Spacer()
                Button("Done") { onClose() }.keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Actions

    private var canSave: Bool {
        switch method {
        case .apiKey, .sessionToken: return !secret.trimmingCharacters(in: .whitespaces).isEmpty
        case .detectClaudeCode, .detectCodex, .manual, .oauth: return true
        default: return false
        }
    }

    private func loadCurrent() {
        let c = connections.connection(for: providerID)
        method = c.method == .none ? (methods.first ?? .manual) : c.method
        manualSession = (c.manualSession ?? 0) * 100
        manualWeekly = (c.manualWeekly ?? 0) * 100
        oauthConfig = connections.oauthConfig(for: providerID)
        secret = ""
        signInError = nil
    }

    private func attemptSave() {
        if providerID == .claude && method.isSubscriptionAuth {
            showConsent = true
        } else {
            commit()
        }
    }

    private func commit() {
        switch method {
        case .apiKey, .sessionToken:
            connections.vault.store(secret, for: providerID, method: method)
        case .manual:
            connections.setManual(session: manualSession / 100, weekly: manualWeekly / 100, for: providerID)
        case .oauth:
            connections.setOAuthConfig(oauthConfig, for: providerID)
        default:
            break
        }
        connections.setMethod(method, for: providerID)
        runTest()
    }

    private func signIn() {
        connections.setOAuthConfig(oauthConfig, for: providerID)
        if providerID == .claude {
            consentThenSignIn = true
            showConsent = true
            return
        }
        performSignIn()
    }

    private func performSignIn() {
        connections.setOAuthConfig(oauthConfig, for: providerID)
        isSigningIn = true; signInError = nil
        Task {
            do {
                let tokens = try await flow.signIn(config: oauthConfig, useSystemBrowser: useSystemBrowser)
                connections.vault.store(tokens.accessToken, for: providerID, method: .oauth)
                connections.setMethod(.oauth, for: providerID)
                isSigningIn = false
                runTest()
            } catch {
                isSigningIn = false
                signInError = error.localizedDescription
            }
        }
    }

    /// Reload the saved connection and run the connection test (the wizard's final step).
    private func runTest() {
        stage = .testing
        let id = providerID
        let conn = connections.connection(for: id)
        let vault = connections.vault
        Task {
            let result = await ConnectionTester.test(id: id, connection: conn, vault: vault)
            testResult = result
            stage = .result
        }
    }
}
