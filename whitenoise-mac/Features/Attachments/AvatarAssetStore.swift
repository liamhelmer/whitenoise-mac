import Foundation
import MarmotKit
import Observation

/// Account-scoped durable avatar bytes. Remote URLs remain a presentation fallback when a
/// target has no ready retained asset or the bounded read is deferred.
@MainActor
@Observable
final class AvatarAssetStore {
    private(set) var assetsByTarget: [String: AvatarAssetFfi] = [:]
    private(set) var bytesByReference: [String: AvatarBytesFfi] = [:]
    private(set) var error: String?

    @ObservationIgnored private let accountRef: String
    @ObservationIgnored private let runtime: any MarmotRuntime

    init(accountRef: String, runtime: any MarmotRuntime) {
        self.accountRef = accountRef
        self.runtime = runtime
    }

    func request(targets: [String], maxBytes: UInt64 = 8 * 1_024 * 1_024) async {
        guard !targets.isEmpty else { return }
        do {
            let assets = try await runtime.requestAvatarAssets(accountRef: accountRef, targets: targets)
            for asset in assets { assetsByTarget[asset.target] = asset }
            let references = assets.compactMap { asset -> String? in
                guard asset.availability == .ready else { return nil }
                return asset.reference
            }
            guard !references.isEmpty else {
                error = nil
                return
            }
            let payloads = try await runtime.readAvatarAssets(
                accountRef: accountRef, references: references, maxBytes: maxBytes
            )
            for payload in payloads where payload.availability == .ready && !payload.deferred {
                bytesByReference[payload.reference] = payload
            }
            error = nil
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }

    func load(assets: [AvatarAssetFfi], maxBytes: UInt64 = 32 * 1_024 * 1_024) async {
        guard !assets.isEmpty else { return }
        for asset in assets { assetsByTarget[asset.target] = asset }
        let references = Array(
            Set(
                assets.compactMap { asset in
                    asset.availability == .ready ? asset.reference : nil
                }))
        guard !references.isEmpty else { return }
        do {
            let payloads = try await runtime.readAvatarAssets(
                accountRef: accountRef,
                references: references,
                maxBytes: maxBytes
            )
            try Task.checkCancellation()
            for payload in payloads where payload.availability == .ready && !payload.deferred {
                bytesByReference[payload.reference] = payload
            }
            error = nil
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }

    func clear() async {
        do {
            try await runtime.clearAvatarCache(accountRef: accountRef)
            assetsByTarget.removeAll()
            bytesByReference.removeAll()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
