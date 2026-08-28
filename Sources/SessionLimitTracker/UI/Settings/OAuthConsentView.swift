import SwiftUI

/// Consent gate shown before any subscription-token method is enabled. The user
/// must explicitly acknowledge the policy + reliability caveats.
struct OAuthConsentView: View {
    var onAccept: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Before linking your account", systemImage: "exclamationmark.shield")
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                bullet("This reads your Claude subscription token to fetch real, shared-pool usage numbers.")
                bullet("Anthropic's terms restrict third-party use of subscription tokens. This is your own account and data, but it's a gray area that could break or, in the worst case, risk account action.")
                bullet("The usage endpoint is undocumented and rate-limits hard — polling is capped at once every ~3 minutes.")
                bullet("Your token is read live from the Keychain per request. It is never copied, logged, or sent anywhere else.")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            Spacer()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                Button("I understand — enable") { onAccept() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460, height: 300)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text(text)
        }
    }
}
