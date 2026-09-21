import Foundation
import MarmotKit
import Observation

enum DiagnosticsSettingsError: Equatable {
    case unavailable(String)

    var message: String {
        switch self {
        case .unavailable(let message): message
        }
    }
}

@MainActor
@Observable
final class DiagnosticsSettingsViewModel {
    private(set) var settings: UsageDiagnosticsSettingsFfi?
    private(set) var status: UsageDiagnosticsStatusFfi?
    private(set) var auditSettings: AuditLogSettingsFfi?
    private(set) var auditLogFiles: [AuditLogFileFfi] = []
    private(set) var isLoading = false
    private(set) var isSavingUsage = false
    private(set) var isSavingAudit = false
    private(set) var isLoadingAuditLogs = false
    private(set) var isDeletingAuditLogs = false
    private(set) var isUploadingAuditLogs = false
    private(set) var auditUploadStatus: String?
    private(set) var error: DiagnosticsSettingsError?

    @ObservationIgnored private let runtime: (any MarmotRuntime)?
    @ObservationIgnored private let productAnalytics: ProductAnalyticsRecorder?

    init(
        runtime: (any MarmotRuntime)?,
        productAnalytics: ProductAnalyticsRecorder? = nil
    ) {
        self.runtime = runtime
        self.productAnalytics = productAnalytics
    }

    func load() async {
        guard let runtime, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await FFIExecutor.run { [runtime] in
                (
                    try runtime.usageDiagnosticsSettings(),
                    try runtime.usageDiagnosticsStatus(),
                    try runtime.auditLogSettings()
                )
            }
            guard !Task.isCancelled else { return }
            settings = loaded.0
            status = loaded.1
            auditSettings = loaded.2
            configureProductAnalytics(for: loaded.0)
            error = nil
            await loadAuditLogs()
        } catch is CancellationError {
            return
        } catch {
            productAnalytics?.deactivate()
            self.error = .unavailable(error.localizedDescription)
        }
    }

    func setEnabled(_ enabled: Bool) async {
        guard let runtime, !isSavingUsage else { return }
        isSavingUsage = true
        defer { isSavingUsage = false }
        do {
            settings = try await FFIExecutor.run { [runtime] in
                try runtime.setUsageDiagnosticsConsent(enabled: enabled)
            }
            status = try await FFIExecutor.run { [runtime] in try runtime.usageDiagnosticsStatus() }
            if let settings {
                configureProductAnalytics(for: settings)
            }
            error = nil
        } catch is CancellationError {
            return
        } catch {
            productAnalytics?.deactivate()
            self.error = .unavailable(error.localizedDescription)
        }
    }

    func setAuditEnabled(_ enabled: Bool) async {
        guard let runtime, !isSavingAudit else { return }
        isSavingAudit = true
        defer { isSavingAudit = false }
        do {
            auditSettings = try await runtime.setAuditLogSettings(
                settings: AuditLogSettingsFfi(enabled: enabled)
            )
            error = nil
            await loadAuditLogs()
        } catch is CancellationError {
            return
        } catch {
            self.error = .unavailable(error.localizedDescription)
        }
    }

    func refresh() async {
        await load()
    }

    func flush() async {
        guard let runtime else { return }
        do {
            try await runtime.flushProductAnalytics()
            guard !Task.isCancelled else { return }
            status = try await FFIExecutor.run { [runtime] in try runtime.usageDiagnosticsStatus() }
            error = nil
        } catch is CancellationError {
            return
        } catch {
            self.error = .unavailable(error.localizedDescription)
        }
    }

    func loadAuditLogs() async {
        guard let runtime, !isLoadingAuditLogs else { return }
        isLoadingAuditLogs = true
        defer { isLoadingAuditLogs = false }
        do {
            let files = try await FFIExecutor.run { [runtime] in try runtime.auditLogFiles() }
            try Task.checkCancellation()
            auditLogFiles = files
            error = nil
        } catch is CancellationError {
            return
        } catch {
            auditLogFiles = []
            self.error = .unavailable(error.localizedDescription)
        }
    }

    func deleteAllAuditLogs() async {
        guard let runtime, !isDeletingAuditLogs else { return }
        isDeletingAuditLogs = true
        auditUploadStatus = nil
        defer { isDeletingAuditLogs = false }
        do {
            for file in auditLogFiles {
                _ = try await runtime.deleteAuditLogFile(path: file.path)
            }
            error = nil
        } catch is CancellationError {
            return
        } catch {
            self.error = .unavailable(error.localizedDescription)
        }
        await loadAuditLogs()
    }

    func uploadAuditLogs() async {
        guard let runtime, !isUploadingAuditLogs else { return }
        isUploadingAuditLogs = true
        auditUploadStatus = nil
        defer { isUploadingAuditLogs = false }
        do {
            let result = try await runtime.postAuditLogTrackerUpdate()
            auditUploadStatus = Self.auditUploadStatusMessage(result)
            error = nil
            await loadAuditLogs()
        } catch is CancellationError {
            return
        } catch {
            self.error = .unavailable(error.localizedDescription)
        }
    }

    func diagnosticLogExport(path: String? = nil) async throws -> DiagnosticLogSnapshot {
        guard let runtime else { throw DiagnosticLogExport.ExportError.noLogs }
        let files = try await FFIExecutor.run { [runtime] in try runtime.auditLogFiles() }
        let file = try DiagnosticLogExport.fileForExport(in: files, path: path)
        for attempt in 0..<3 {
            do {
                return try await Task.detached(priority: .userInitiated) {
                    try DiagnosticLogExport.snapshot(file: file)
                }.value
            } catch DiagnosticLogExport.ExportError.fileChangedDuringRead where attempt < 2 {
                try await Task.sleep(for: .milliseconds(25))
            }
        }
        throw DiagnosticLogExport.ExportError.fileChangedDuringRead
    }

    static func preview() -> DiagnosticsSettingsViewModel {
        DiagnosticsSettingsViewModel(runtime: nil)
    }

    private func configureProductAnalytics(for settings: UsageDiagnosticsSettingsFfi) {
        guard settings.decision == .granted, let runtime, let productAnalytics else {
            productAnalytics?.deactivate()
            return
        }
        productAnalytics.activate(
            event: { event in
                _ = try? runtime.recordProductEvent(event: event.ffi)
            },
            timing: { stage, durationMs, outcome in
                _ = try runtime.recordHostTiming(
                    name: stage.rawValue,
                    durationMs: durationMs,
                    outcome: outcome
                )
            }
        )
    }

    private static func auditUploadStatusMessage(_ result: AuditLogTrackerUpdateResultFfi) -> String {
        if let skippedReason = result.skippedReason, !skippedReason.isEmpty {
            return String(format: L10n.string("Audit upload skipped: %@"), skippedReason)
        }
        guard !result.uploaded.isEmpty else {
            return L10n.string("No audit logs uploaded.")
        }
        let totalBytes = result.uploaded.reduce(UInt64(0)) { $0 + $1.bytesSent }
        return String(
            format: L10n.string("Uploaded %d audit log files (%@)."),
            result.uploaded.count,
            ByteCountFormatter.string(
                fromByteCount: Int64(clamping: totalBytes),
                countStyle: .file
            )
        )
    }
}
