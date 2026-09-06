import Foundation

public enum RecordingPhase: Equatable, Sendable {
    case preparing, ready, countdown(Int), starting, recording, finishing, review, failed

    public var locksControls: Bool {
        switch self {
        case .preparing, .countdown, .starting, .recording, .finishing: true
        default: false
        }
    }
}

public enum RecordingEvent: Sendable {
    case prepared, count(Int), requestStart, didStart, stop, didFinish, cancelCountdown, fail, retry
}

public struct RecordingState: Sendable {
    public private(set) var phase: RecordingPhase = .preparing
    public init() {}

    @discardableResult public mutating func apply(_ event: RecordingEvent) -> Bool {
        let next: RecordingPhase
        switch (phase, event) {
        case (.preparing, .prepared): next = .ready
        case (.ready, .count(let seconds)) where seconds > 0: next = .countdown(seconds)
        case (.countdown, .count(let seconds)) where seconds > 0: next = .countdown(seconds)
        case (.ready, .requestStart), (.countdown, .requestStart): next = .starting
        case (.starting, .didStart): next = .recording
        case (.starting, .stop), (.recording, .stop): next = .finishing
        case (.starting, .didFinish), (.recording, .didFinish), (.finishing, .didFinish): next = .review
        case (.countdown, .cancelCountdown): next = .ready
        case (.failed, .retry), (.review, .retry), (.ready, .retry): next = .preparing
        case (_, .fail): next = .failed
        default: return false
        }
        phase = next
        return true
    }
}

