import Testing
#if SWIFT_PACKAGE
@testable import SuflerCore
#else
@testable import Sufler
#endif

@Test func recordRequiresActualCameraStart() {
    var state = RecordingState()
    let requestStartTooEarly = state.apply(.requestStart)
    #expect(!requestStartTooEarly)
    let prepared = state.apply(.prepared)
    #expect(prepared)
    let counted = state.apply(.count(3))
    #expect(counted)
    let requestStart = state.apply(.requestStart)
    #expect(requestStart)
    #expect(state.phase == .starting)
    let requestStartWhileStarting = state.apply(.requestStart)
    #expect(!requestStartWhileStarting)
    let didStart = state.apply(.didStart)
    #expect(didStart)
    #expect(state.phase == .recording)
    let requestStartWhileRecording = state.apply(.requestStart)
    #expect(!requestStartWhileRecording)
    let stop = state.apply(.stop)
    #expect(stop)
    let stopAgain = state.apply(.stop)
    #expect(!stopAgain)
    #expect(state.phase == .finishing)
    let didFinish = state.apply(.didFinish)
    #expect(didFinish)
    #expect(state.phase == .review)
}

@Test func cancellingCountdownDoesNotStartRecording() {
    var state = RecordingState()
    state.apply(.prepared); state.apply(.count(5)); state.apply(.cancelCountdown)
    #expect(state.phase == .ready)
    let didStart = state.apply(.didStart)
    #expect(!didStart)
    let didFinish = state.apply(.didFinish)
    #expect(!didFinish)
}

@Test func interruptionDuringStartIgnoresLateStartCallback() {
    var state = RecordingState()
    state.apply(.prepared); state.apply(.requestStart); state.apply(.stop)
    let didStart = state.apply(.didStart)
    #expect(!didStart)
    #expect(state.phase == .finishing)
    let didFinish = state.apply(.didFinish)
    #expect(didFinish)
}

@Test func failedAndCompletedRecordingsNeedExplicitRetry() {
    var state = RecordingState()
    state.apply(.prepared); state.apply(.fail)
    let preparedAfterFail = state.apply(.prepared)
    #expect(!preparedAfterFail)
    let requestStartAfterFail = state.apply(.requestStart)
    #expect(!requestStartAfterFail)
    let retry = state.apply(.retry)
    #expect(retry)
    #expect(state.phase == .preparing)
}
