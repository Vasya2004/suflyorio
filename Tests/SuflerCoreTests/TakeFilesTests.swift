import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import SuflerCore
#else
@testable import Sufler
#endif

@Test func journalPersistsAcrossInstancesAndDeduplicates() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let files = try TakeFiles(directory: root)
    let intent = TakeIntent(title: "Русский сценарий")
    try files.register(intent)
    try Data([1, 2, 3]).write(to: files.movieURL(for: intent.id))
    let reopened = try TakeFiles(directory: root)
    #expect(try reopened.candidates() == [intent])
}

@Test func orphanMovieIsRecoveredEvenWithCorruptJournal() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let files = try TakeFiles(directory: root)
    let id = UUID()
    try Data([1]).write(to: files.movieURL(for: id))
    try Data("broken".utf8).write(to: files.journalURL(for: id))
    #expect(try files.candidates().map(\.id) == [id])
    try files.remove(id)
    #expect(try files.candidates().isEmpty)
}
