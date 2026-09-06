import Foundation

/// Positions are points, speed is points/second. No assumed screen refresh rate.
public struct ScrollClock: Sendable {
    public private(set) var offset: Double = 0
    private var lastTimestamp: Double?

    public init() {}

    public mutating func tick(at timestamp: Double, speed: Double, limit: Double, running: Bool) -> Double {
        defer { lastTimestamp = timestamp }
        guard running, let lastTimestamp, timestamp.isFinite, speed.isFinite else { return offset }
        // Discard long gaps (backgrounding/debugger stalls), rather than jumping through the script.
        let delta = timestamp - lastTimestamp
        guard delta > 0, delta < 0.5 else { return offset }
        offset = min(max(0, limit), max(0, offset + max(0, speed) * delta))
        return offset
    }

    public mutating func seek(to value: Double, limit: Double) {
        offset = min(max(0, limit), max(0, value.isFinite ? value : 0))
        lastTimestamp = nil
    }

    public mutating func suspend() { lastTimestamp = nil }
}

