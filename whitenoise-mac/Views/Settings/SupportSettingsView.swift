import SwiftUI

struct SupportSettingsView: View {
    var body: some View {
        SettingsScaffold(title: L10n.string("Support")) {
            SettingsSection(
                title: L10n.string("White Noise Support"),
                footer: L10n.string("Ask how something works, report a problem, or share a suggestion.")
            ) {
                Link(destination: URL(string: "https://whitenoise.chat")!) {
                    Label(L10n.string("Website"), systemImage: "safari")
                }

                Link(destination: URL(string: "mailto:support@whitenoise.chat")!) {
                    Label(L10n.string("Chat with support"), systemImage: "message")
                }
            }
        }
    }
}

#Preview {
    SupportSettingsView()
        .environment(WorkspaceState.preview())
        .frame(width: 760, height: 640)
}
