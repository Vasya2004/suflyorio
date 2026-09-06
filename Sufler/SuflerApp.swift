import SwiftUI
import SwiftData

@main @MainActor struct SuflerApp: App {
    private let startup: Result<LibraryStore, Error>
    init() { startup = Result { try LibraryStore() } }

    var body: some Scene {
        WindowGroup {
            switch startup {
            case .success(let library):
                LibraryView()
                    .environmentObject(library)
                    .modelContainer(library.container)
                    .tint(Style.green)
                    .task { await library.recover() }
            case .failure(let error):
                ContentUnavailableView {
                    Label("Не удалось открыть библиотеку", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text("Ваши файлы не удалены. Освободите память и перезапустите приложение.\n\n\(error.localizedDescription)")
                }
            }
        }
    }
}

