import MarmotKit
import SwiftUI

/// The two device-wide diagnostics decisions share one feature model on both the settings page
/// and the first-run prompt. MarmotKit owns the usage consent receipt; audit-log recording remains
/// an independent choice because it controls durable group diagnostics on this Mac.
struct DataSharingToggleRows: View {
    let model: DiagnosticsSettingsViewModel

    var body: some View {
        WNToggle(
            L10n.string("Share usage and telemetry"),
            systemImage: "waveform.path.ecg",
            isOn: Binding(
                get: { model.settings?.decision == .granted },
                set: { enabled in Task { await model.setEnabled(enabled) } }
            )
        )
        .disabled(model.settings == nil || model.isLoading || model.isSavingUsage)

        WNToggle(
            L10n.string("Share group diagnostic logs"),
            systemImage: "doc.text.magnifyingglass",
            isOn: Binding(
                get: { model.auditSettings?.enabled == true },
                set: { enabled in Task { await model.setAuditEnabled(enabled) } }
            )
        )
        .disabled(model.auditSettings == nil || model.isLoading || model.isSavingAudit)

        if model.isSavingUsage || model.isSavingAudit {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(L10n.string("Saving..."))
                    .foregroundStyle(WNColor.backgroundContentSecondary)
            }
        }
    }
}

#Preview {
    Form {
        DataSharingToggleRows(model: .preview())
    }
    .frame(width: 520, height: 240)
}
