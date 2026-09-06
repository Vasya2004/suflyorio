import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import SuflerCore
#else
@testable import Sufler
#endif

private final class MovieFixtureMarker {}

private func movieFixture(_ name: String) -> URL {
    #if STANDALONE_CHECKS
    return URL(fileURLWithPath: ProcessInfo.processInfo.environment["SUFLER_FIXTURES"]!).appendingPathComponent(name + ".mov")
    #elseif SWIFT_PACKAGE
    return Bundle.module.url(forResource: name, withExtension: "mov", subdirectory: "Fixtures")!
    #else
    return Bundle(for: MovieFixtureMarker.self).url(forResource: name, withExtension: "mov")!
    #endif
}

@Test func acceptsPlayableMovieWithVideoAndAudio() async {
    let duration = await MovieValidation.playableDuration(movieFixture("valid"))
    #expect(abs((duration ?? 0) - 0.4) < 0.1)
}

@Test func rejectsVideoWithoutAudio() async {
    let duration = await MovieValidation.playableDuration(movieFixture("no-audio"))
    #expect(duration == nil)
}

@Test func rejectsMissingAndCorruptMovies() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("bad.mov")
    let missing = await MovieValidation.playableDuration(url)
    #expect(missing == nil)
    try Data("truncated movie".utf8).write(to: url)
    let corrupt = await MovieValidation.playableDuration(url)
    #expect(corrupt == nil)
}
