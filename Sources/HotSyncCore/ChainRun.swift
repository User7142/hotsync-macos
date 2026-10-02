import Foundation

/// The run of a sync chain ("A, then B, then C"): which step is due, and
/// what happens when a step fails - the chain pauses on that step until the
/// user retries, skips it or cancels the chain.
public struct ChainRun: Equatable, Sendable {

    public enum State: Equatable, Sendable {
        case running(step: Int)
        case paused(step: Int, reason: String)
        case finished
        case cancelled
    }

    public let steps: [UUID]
    public private(set) var state: State
    /// steps that were skipped after a failure, for the summary
    public private(set) var skipped: [Int] = []

    public init(steps: [UUID]) {
        self.steps = steps
        self.state = steps.isEmpty ? .finished : .running(step: 0)
    }

    /// The tab whose session runs (or waits to be retried).
    public var currentTab: UUID? {
        switch state {
        case .running(let step), .paused(let step, _): return steps[step]
        case .finished, .cancelled: return nil
        }
    }

    public var isActive: Bool {
        switch state {
        case .running, .paused: return true
        case .finished, .cancelled: return false
        }
    }

    /// The running step ended successfully: on to the next one.
    public mutating func stepSucceeded() {
        guard case .running(let step) = state else { return }
        advance(from: step)
    }

    /// The running step failed: pause on it.
    public mutating func stepFailed(reason: String) {
        guard case .running(let step) = state else { return }
        state = .paused(step: step, reason: reason)
    }

    /// Runs the paused step again.
    public mutating func retry() {
        guard case .paused(let step, _) = state else { return }
        state = .running(step: step)
    }

    /// Leaves the paused step out and goes on with the next one.
    public mutating func skip() {
        guard case .paused(let step, _) = state else { return }
        skipped.append(step)
        advance(from: step)
    }

    public mutating func cancel() {
        guard isActive else { return }
        state = .cancelled
    }

    private mutating func advance(from step: Int) {
        state = step + 1 < steps.count ? .running(step: step + 1) : .finished
    }
}
