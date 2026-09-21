import MarmotKit
import SwiftUI

nonisolated enum ReportPresentation {
    static let reasons: [ReportReasonFfi] = [
        .spam, .nudity, .malware, .profanity, .illegal, .impersonation, .other,
    ]

    static func title(_ reason: ReportReasonFfi) -> String {
        switch reason {
        case .spam: L10n.string("Spam")
        case .nudity: L10n.string("Nudity")
        case .malware: L10n.string("Malware")
        case .profanity: L10n.string("Profanity")
        case .illegal: L10n.string("Illegal content")
        case .impersonation: L10n.string("Impersonation")
        case .other: L10n.string("Other")
        }
    }
}

struct ReportMessageSheet: View {
    let message: MessageItem
    let model: GroupSafetyViewModel
    let dismiss: () -> Void
    @State private var reason: ReportReasonFfi = .spam
    @State private var explanation = ""
    @State private var isSending = false
    @State private var error: String?
    @State private var operation: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.string("Report Message"))
                .wnFont(.semiBold18)

            Picker(L10n.string("Reason"), selection: $reason) {
                ForEach(ReportPresentation.reasons, id: \.self) { reason in
                    Text(ReportPresentation.title(reason)).tag(reason)
                }
            }

            TextField(
                L10n.string("Explanation (optional)"),
                text: $explanation,
                axis: .vertical
            )
            .lineLimit(3...6)
            .onChange(of: explanation) { _, value in
                explanation = String(value.prefix(1_000))
            }

            Text(
                L10n.string(
                    "Reports are shared inside this encrypted group. Group members can read your report and explanation."
                )
            )
            .wnFont(.medium10)
            .foregroundStyle(WNColor.backgroundContentSecondary)
            .fixedSize(horizontal: false, vertical: true)

            if let error {
                SettingsErrorView(error: error)
            }

            HStack {
                Button(L10n.string("Cancel"), action: dismiss)
                    .disabled(isSending)
                Spacer()
                Button(L10n.string("Report")) {
                    operation = Task { await submit() }
                }
                .nativeGlassProminentButtonStyle()
                .disabled(isSending || !message.canReport)
            }
        }
        .padding(24)
        .frame(width: 520)
        .interactiveDismissDisabled(isSending)
        .onDisappear {
            operation?.cancel()
            operation = nil
        }
    }

    private func submit() async {
        guard !isSending, message.canReport else { return }
        isSending = true
        error = nil
        defer { isSending = false }
        do {
            try await model.report(
                messageID: message.id,
                reason: reason,
                explanation: explanation
            )
            try Task.checkCancellation()
            dismiss()
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct ReportReasonPickerPreview: View {
    @State private var reason: ReportReasonFfi = .spam

    var body: some View {
        Picker(L10n.string("Reason"), selection: $reason) {
            ForEach(ReportPresentation.reasons, id: \.self) { reason in
                Text(ReportPresentation.title(reason)).tag(reason)
            }
        }
        .padding()
        .frame(width: 360)
    }
}

#Preview {
    ReportReasonPickerPreview()
}
