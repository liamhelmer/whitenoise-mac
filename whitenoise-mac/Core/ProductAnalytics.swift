import Foundation
import MarmotKit
import Synchronization

nonisolated enum ProductScreen: String, Hashable, Sendable {
    case inbox
    case conversation
    case settings
}

nonisolated enum ProductEvent: Sendable {
    case screen(ProductScreen)

    var ffi: ProductEventFfi {
        switch self {
        case .screen(let screen):
            ProductEventFfi(
                name: "app_screen_viewed",
                properties: [ProductEventPropertyFfi(name: "screen", value: screen.rawValue)]
            )
        }
    }
}

/// Consent-generation gate for host observations. Tickets only admit work that began while the
/// current runtime had confirmed consent; disabling diagnostics invalidates every outstanding
/// ticket before a queued observation can cross the FFI boundary.
nonisolated final class ProductAnalyticsRecorder: Sendable {
    struct Ticket: Hashable, Sendable {
        fileprivate let generation: UUID
    }

    struct Timing: Sendable {
        fileprivate let ticket: Ticket
        fileprivate let startedAt: ContinuousClock.Instant
    }

    private struct State: Sendable {
        var generation = UUID()
        var eventSink: (@Sendable (ProductEvent) -> Void)?
        var timingSink: (@Sendable (ProductAnalyticsTimingStage, UInt64, HostPerformanceOutcomeFfi) throws -> Void)?
        var pending = 0
    }

    private let state = Mutex(State())

    func activate(
        event: @escaping @Sendable (ProductEvent) -> Void,
        timing: @escaping @Sendable (ProductAnalyticsTimingStage, UInt64, HostPerformanceOutcomeFfi) throws -> Void
    ) {
        state.withLock {
            $0.eventSink = event
            $0.timingSink = timing
        }
    }

    func deactivate() {
        state.withLock {
            $0.generation = UUID()
            $0.eventSink = nil
            $0.timingSink = nil
        }
    }

    func ticket() -> Ticket? {
        state.withLock { state in
            state.eventSink == nil ? nil : Ticket(generation: state.generation)
        }
    }

    @discardableResult
    func record(_ event: ProductEvent, ticket: Ticket? = nil) -> Task<Void, Never>? {
        let admittedTicket = ticket ?? self.ticket()
        return enqueue(ticket: admittedTicket) { state in
            state.eventSink?(event)
        }
    }

    func beginTiming(at now: ContinuousClock.Instant = .now) -> Timing? {
        state.withLock { state in
            guard state.eventSink != nil, state.timingSink != nil else { return nil }
            return Timing(ticket: Ticket(generation: state.generation), startedAt: now)
        }
    }

    @discardableResult
    func recordTiming(
        _ stage: ProductAnalyticsTimingStage,
        since timing: Timing?,
        outcome: HostPerformanceOutcomeFfi = .success,
        at now: ContinuousClock.Instant = .now
    ) -> Task<Void, Never>? {
        guard let timing else { return nil }
        let elapsed = timing.startedAt.duration(to: max(timing.startedAt, now)).components
        let seconds = UInt64(max(0, elapsed.seconds))
        let fractionalMilliseconds = UInt64(max(0, elapsed.attoseconds)) / 1_000_000_000_000_000
        let (wholeMilliseconds, multiplicationOverflow) = seconds.multipliedReportingOverflow(by: 1_000)
        let (milliseconds, additionOverflow) = wholeMilliseconds.addingReportingOverflow(fractionalMilliseconds)
        return enqueue(ticket: timing.ticket) { state in
            try state.timingSink?(
                stage,
                multiplicationOverflow || additionOverflow ? .max : milliseconds,
                outcome
            )
        }
    }

    private func enqueue(
        ticket: Ticket?,
        deliver: @escaping @Sendable (inout State) throws -> Void
    ) -> Task<Void, Never>? {
        guard let ticket else { return nil }
        let admitted = state.withLock { state in
            guard state.generation == ticket.generation,
                state.eventSink != nil,
                state.pending < 64
            else { return false }
            state.pending += 1
            return true
        }
        guard admitted else { return nil }
        return Task.detached(priority: .utility) { [self] in
            state.withLock { state in
                defer { state.pending -= 1 }
                guard state.generation == ticket.generation else { return }
                do {
                    try deliver(&state)
                } catch {
                    state.generation = UUID()
                    state.eventSink = nil
                    state.timingSink = nil
                }
            }
        }
    }
}
