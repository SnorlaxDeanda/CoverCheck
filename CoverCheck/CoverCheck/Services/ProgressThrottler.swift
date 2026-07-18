import Foundation

/// Limits how often progress callbacks hit the UI (avoids SwiftUI / IPC rate-limit spam).
actor ProgressThrottler<Value: Equatable & Sendable> {
    private let interval: Duration
    private var lastEmit: ContinuousClock.Instant?
    private var pending: Value?
    private var lastEmitted: Value?

    init(intervalMilliseconds: Int = 100) {
        self.interval = .milliseconds(intervalMilliseconds)
    }

    /// Emit immediately for the first value, then at most once per interval. Always flushes the latest.
    func submit(_ value: Value, force: Bool = false, emit: @MainActor @escaping (Value) -> Void) async {
        if !force, let lastEmitted, lastEmitted == value {
            return
        }

        let now = ContinuousClock.now
        if force || lastEmit == nil || lastEmit!.duration(to: now) >= interval {
            lastEmit = now
            lastEmitted = value
            pending = nil
            await emit(value)
        } else {
            pending = value
        }
    }

    func flush(emit: @MainActor @escaping (Value) -> Void) async {
        guard let pending else { return }
        let value = pending
        self.pending = nil
        lastEmit = ContinuousClock.now
        lastEmitted = value
        await emit(value)
    }
}
