import Foundation
import SwiftData
import Testing
#if SWIFT_PACKAGE
import SuflerCore
@testable import SuflerStorage
#else
@testable import Sufler
#endif

private final class FixtureBundleMarker {}

@Suite @MainActor struct LibraryStoreTests {
    private func fixture() throws -> URL {
        #if SWIFT_PACKAGE
        return try #require(Bundle.module.url(forResource: "valid", withExtension: "mov", subdirectory: "Fixtures"))
        #else
        return try #require(Bundle(for: FixtureBundleMarker.self).url(forResource: "valid", withExtension: "mov"))
        #endif
    }

    private func makeStore(_ root: URL) throws -> LibraryStore {
        try LibraryStore(configuration: ModelConfiguration(isStoredInMemoryOnly: true), directory: root)
    }

    @Test func preservesPlayablePartialRecordingAndRecoversOnlyOnce() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try makeStore(root)
        let intent = TakeIntent(title: "Прерванный дубль")
        try store.files.register(intent)
        try FileManager.default.copyItem(at: fixture(), to: store.files.movieURL(for: intent.id))
        await store.recover()
        await store.recover()
        let takes = try store.context.fetch(FetchDescriptor<Take>())
        #expect(takes.count == 1)
        #expect(takes.first?.id == intent.id)
        #expect(takes.first?.status == "ready")
        #expect((takes.first?.duration ?? 0) > 0)
    }

    @Test func invalidAndMissingFilesAreNeverReportedAsSuccessful() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try makeStore(root)
        let corrupt = try store.beginTake(title: "Повреждённый")
        try Data("invalid movie".utf8).write(to: store.files.movieURL(for: corrupt.id))
        #expect(await store.finalize(corrupt) == false)
        #expect(corrupt.status == "unavailable")
        #expect(FileManager.default.fileExists(atPath: store.files.movieURL(for: corrupt.id).path))
        let missing = try store.beginTake(title: "Нет файла")
        #expect(await store.finalize(missing) == false)
        #expect(missing.status == "unavailable")
    }

    @Test func completedTakeSurvivesFailureNoteAndDoesNotOverwritePrevious() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try makeStore(root)
        let first = try store.beginTake(title: "Первый")
        let second = try store.beginTake(title: "Второй")
        #expect(first.id != second.id)
        try FileManager.default.copyItem(at: fixture(), to: store.files.movieURL(for: first.id))
        #expect(await store.finalize(first, note: "Запись прервана") == true)
        #expect(first.note == "Запись прервана")
        #expect(first.status == "ready")
        store.deleteTake(second)
        #expect(FileManager.default.fileExists(atPath: store.files.movieURL(for: first.id).path))
    }

    @Test func scriptsAndSettingsPersistAcrossContainersWithoutReseeding() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = root.appendingPathComponent("test.store")
        let movies = root.appendingPathComponent("Takes")
        do {
            let store = try LibraryStore(configuration: ModelConfiguration(url: database), directory: movies)
            let scripts = try store.context.fetch(FetchDescriptor<Script>())
            #expect(scripts.count == 1)
            scripts.forEach(store.context.delete)
            store.context.insert(Script(title: "Мой текст", text: "Привет, мир!"))
            store.settings.speed = 73
            #expect(store.save())
        }
        let reopened = try LibraryStore(configuration: ModelConfiguration(url: database), directory: movies)
        let scripts = try reopened.context.fetch(FetchDescriptor<Script>())
        #expect(scripts.count == 1)
        #expect(scripts.first?.text == "Привет, мир!")
        #expect(reopened.settings.speed == 73)
    }
}
