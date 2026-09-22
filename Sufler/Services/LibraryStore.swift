import AVFoundation
import Combine
import SwiftData
import Foundation
#if SWIFT_PACKAGE
import SuflerCore
#endif

@MainActor final class LibraryStore: ObservableObject {
    let container: ModelContainer
    let files: TakeFiles
    let settings: PromptSettings
    var context: ModelContext { container.mainContext }
    @Published var errorMessage: String?
    @Published var recovering = true

    init(configuration: ModelConfiguration? = nil, directory customDirectory: URL? = nil) throws {
        let schema = Schema([Script.self, PromptSettings.self, Take.self])
        let configurations: [ModelConfiguration] = configuration.map { [$0] } ?? []
        container = try ModelContainer(for: schema, configurations: configurations)
        let directory = try customDirectory ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true).appendingPathComponent("Takes", isDirectory: true)
        files = try TakeFiles(directory: directory)
        let context = container.mainContext
        settings = try context.fetch(FetchDescriptor<PromptSettings>()).first ?? PromptSettings()
        if settings.modelContext == nil { context.insert(settings) }
        if !settings.didSeedExample {
            if try context.fetchCount(FetchDescriptor<Script>()) == 0 {
                context.insert(Script(title: "Мой первый дубль", text: "Привет! Это моя первая запись с суфлёром.\n\nЯ смотрю в камеру и спокойно читаю текст. Мне не нужно учить его наизусть.\n\nСначала я выбираю удобную скорость. Если нужно подумать, я могу поставить текст на паузу — видео продолжит записываться.\n\nТеперь можно вставить свой сценарий и рассказать свою историю."))
            }
            settings.didSeedExample = true
        }
        try context.save()
    }

    @discardableResult func save() -> Bool {
        do { try context.save(); return true }
        catch { errorMessage = "Не удалось сохранить изменения: \(error.localizedDescription)"; return false }
    }

    func beginTake(title: String) throws -> Take {
        let intent = TakeIntent(title: title)
        try files.register(intent)
        let take = Take(intent: intent)
        context.insert(take)
        do { try context.save() }
        catch { context.delete(take); throw error }
        return take
    }

    @discardableResult func finalize(_ take: Take, note: String? = nil) async -> Bool {
        if let duration = await MovieValidation.playableDuration(files.movieURL(for: take.id)) {
            take.duration = duration; take.status = "ready"; take.note = note
        } else {
            take.status = "unavailable"
            take.note = FileManager.default.fileExists(atPath: files.movieURL(for: take.id).path)
                ? "Запись не завершена или не содержит видео со звуком. Файл оставлен для восстановления."
                : "Запись не успела сохраниться: файл видео отсутствует."
        }
        let persisted = save()
        return take.status == "ready" && persisted
    }

    func recover() async {
        defer { recovering = false }
        do {
            let existing = try context.fetch(FetchDescriptor<Take>())
            var byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
            for intent in try files.candidates() {
                let take: Take
                if let stored = byID[intent.id] { take = stored }
                else { take = Take(intent: intent); context.insert(take); byID[intent.id] = take }
                if take.status != "ready" { await finalize(take, note: "Дубль найден после повторного запуска.") }
            }
            for take in existing where take.status == "ready" && !FileManager.default.fileExists(atPath: files.movieURL(for: take.id).path) {
                take.status = "unavailable"; take.note = "Файл видео отсутствует."
            }
            save()
            purgeExpiredTakes()
        } catch { errorMessage = "Не удалось проверить сохранённые дубли: \(error.localizedDescription)" }
    }

    private static let takeLifetime: TimeInterval = 7 * 24 * 60 * 60

    func purgeExpiredTakes() {
        guard let expired = try? context.fetch(FetchDescriptor<Take>()).filter({
            Date().timeIntervalSince($0.createdAt) > Self.takeLifetime
        }) else { return }
        for take in expired { deleteTake(take) }
    }

    func deleteTake(_ take: Take) {
        do { try files.remove(take.id); context.delete(take); try context.save() }
        catch { errorMessage = "Не удалось удалить дубль: \(error.localizedDescription)" }
    }
}
