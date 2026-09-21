//
//  MessageEditHistorySheet.swift
//  whitenoise-mac
//
//  The edit-history viewer. Prepared conversations page accepted versions directly from
//  MarmotKit, so history remains complete when its edit rows are outside the visible window.
//

import MarmotKit
import SwiftUI

private struct MessageEditHistoryModifier: ViewModifier {
    @Environment(WorkspaceState.self) private var workspace
    let model: ConversationViewModel

    func body(content: Content) -> some View {
        @Bindable var workspace = workspace

        content.sheet(item: $workspace.messagePendingEditHistory) { message in
            MessageEditHistoryView(message: message, model: model)
        }
    }
}

extension View {
    func messageEditHistory(model: ConversationViewModel) -> some View {
        modifier(MessageEditHistoryModifier(model: model))
    }
}

private struct MessageEditHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    let message: MessageItem
    let model: ConversationViewModel
    @State private var versions: [TimelineEditVersionFfi] = []
    @State private var cursor: TimelineEditVersionFfi?
    @State private var hasMore = false
    @State private var isLoading = false
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L10n.string("Edit history"))
                    .wnFont(.semiBold14)
                Spacer()
                GlassCircleCloseButton { dismiss() }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if versions.isEmpty, !isLoading, !failed {
                        Text(L10n.string("No earlier versions."))
                            .wnFont(.medium12)
                            .foregroundStyle(WNColor.backgroundContentSecondary)
                            .padding(.top, 8)
                    }
                    ForEach(Array(versions.enumerated()), id: \.element.messageIdHex) { index, version in
                        versionRow(version, isLatest: index == 0)
                    }
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                    if failed || hasMore {
                        Button(failed ? L10n.string("Retry") : L10n.string("Load more")) {
                            Task { await loadNextPage() }
                        }
                        .disabled(isLoading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
        }
        .frame(minWidth: 360, minHeight: 320)
        .task(id: message.id) { await loadNextPage() }
    }

    private func versionRow(_ version: TimelineEditVersionFfi, isLatest: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(
                    isLatest ? L10n.string("Current") : L10n.string("Edited")
                )
                .wnFont(.semiBold10)
                .foregroundStyle(
                    isLatest ? WNColor.backgroundContentPrimary : WNColor.backgroundContentSecondary)
                Spacer()
                Text(DisplayText.messageTimestamp(for: Date(timeIntervalSince1970: TimeInterval(version.editedAt))))
                    .wnFont(.medium10)
                    .foregroundStyle(WNColor.backgroundContentSecondary)
            }
            Text(version.plaintext)
                .wnFont(.medium14)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .glassCard()
        }
    }

    @MainActor
    private func loadNextPage() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await model.editHistory(messageIdHex: message.id, before: cursor)
            try Task.checkCancellation()
            let known = Set(versions.map(\.messageIdHex))
            let next = page.versions.reversed().filter { !known.contains($0.messageIdHex) }
            versions.append(contentsOf: next)
            cursor = page.versions.first
            hasMore = page.hasMoreBefore && cursor != nil
            failed = false
        } catch is CancellationError {
            return
        } catch {
            failed = true
        }
    }
}
