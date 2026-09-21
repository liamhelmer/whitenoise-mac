import MarmotKit
import Testing

@testable import whitenoise_mac

@MainActor
struct AccountScopeTests {
    @Test func replacingAccountScopeCancelsTheOldAccount() async throws {
        let runtime = FakeMarmotRuntime(accounts: [])
        let accounts = AccountItem.samples
        let session = SessionState()
        var firstScopeCancelled = false

        await session.activate(account: accounts[0], runtime: runtime, connectivityAvailable: true)
        let firstScope = try #require(session.accountScope)
        firstScope.addCancellation { firstScopeCancelled = true }

        await session.activate(account: accounts[1], runtime: runtime, connectivityAvailable: true)

        #expect(firstScopeCancelled)
        #expect(session.accountScope?.account.id == accounts[1].id)
    }

    @Test func activatingTheSameAccountPreservesItsScope() async throws {
        let runtime = FakeMarmotRuntime(accounts: [])
        let account = AccountItem.samples[0]
        let session = SessionState()

        await session.activate(account: account, runtime: runtime, connectivityAvailable: true)
        let firstScope = try #require(session.accountScope)
        await session.activate(account: account, runtime: runtime, connectivityAvailable: true)

        #expect(session.accountScope === firstScope)
    }

    @Test func deactivationCancelsAndDestroysTheScope() async throws {
        let runtime = FakeMarmotRuntime(accounts: [])
        let session = SessionState()
        var cancelled = false

        await session.activate(account: AccountItem.samples[0], runtime: runtime, connectivityAvailable: true)
        session.accountScope?.addCancellation { cancelled = true }
        await session.deactivate()

        #expect(cancelled)
        #expect(session.accountScope == nil)
    }

    @Test func sessionReportsAccountAndSceneActivityThroughTheScopedRuntime() async {
        let runtime = FakeMarmotRuntime(accounts: [])
        let session = SessionState()

        await session.activate(account: AccountItem.samples[0], runtime: runtime, connectivityAvailable: true)
        await session.updateProductAnalyticsActivity(.foreground)
        await session.updateProductAnalyticsActivity(.background)

        #expect(runtime.productAnalyticsActivities == [.accountChanged, .foreground, .background])
    }
}
