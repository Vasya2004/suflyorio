import Testing
#if SWIFT_PACKAGE
@testable import SuflerCore
#else
@testable import Sufler
#endif

@Test func scrollingIsIndependentOfRefreshRate() {
    for hz in [30, 60, 120] {
        var clock = ScrollClock()
        for frame in 0...hz * 10 {
            _ = clock.tick(at: Double(frame) / Double(hz), speed: 38, limit: 10_000, running: true)
        }
        #expect(abs(clock.offset - 380) < 0.001)
    }
}

@Test func pauseResumeAndBackgroundDoNotJump() {
    var clock = ScrollClock()
    _ = clock.tick(at: 0, speed: 40, limit: 500, running: true)
    _ = clock.tick(at: 0.25, speed: 40, limit: 500, running: true)
    #expect(clock.offset == 10)
    clock.suspend()
    _ = clock.tick(at: 80, speed: 40, limit: 500, running: true)
    #expect(clock.offset == 10)
    _ = clock.tick(at: 80.25, speed: 40, limit: 500, running: true)
    #expect(clock.offset == 20)
    _ = clock.tick(at: 100, speed: 40, limit: 500, running: true)
    #expect(clock.offset == 20)
}

@Test func speedChangesAndManualSeeking() {
    var clock = ScrollClock()
    _ = clock.tick(at: 0, speed: 40, limit: 100, running: true)
    _ = clock.tick(at: 0.25, speed: 40, limit: 100, running: true)
    _ = clock.tick(at: 0.5, speed: 80, limit: 100, running: true)
    #expect(clock.offset == 30)
    clock.seek(to: 98, limit: 100)
    _ = clock.tick(at: 1, speed: 80, limit: 100, running: true)
    _ = clock.tick(at: 1.25, speed: 80, limit: 100, running: true)
    #expect(clock.offset == 100)
    clock.seek(to: -40, limit: 100)
    #expect(clock.offset == 0)
}

@Test func pausedClockAndEmptyContent() {
    var clock = ScrollClock()
    for frame in 0...120 { _ = clock.tick(at: Double(frame) / 60, speed: 40, limit: 0, running: true) }
    #expect(clock.offset == 0)
    clock.seek(to: 30, limit: 500)
    for frame in 0...120 { _ = clock.tick(at: Double(frame) / 60, speed: 40, limit: 500, running: false) }
    #expect(clock.offset == 30)
}

