import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    var body: some View {
        TabView {
            Tab("Тексты", systemImage: "text.alignleft") { ScriptsView() }
            Tab("Дубли", systemImage: "play.rectangle") { TakesView() }
        }
        .alert("Не удалось выполнить действие", isPresented: Binding(get: { library.errorMessage != nil }, set: { if !$0 { library.errorMessage = nil } })) {
            Button("Повторить сохранение") { library.save() }
            Button("Закрыть", role: .cancel) { library.errorMessage = nil }
        } message: { Text(library.errorMessage ?? "") }
    }
}

struct ScriptsView: View {
    @EnvironmentObject private var library: LibraryStore
    @Query(sort: \Script.updatedAt, order: .reverse) private var scripts: [Script]
    @State private var search = ""
    @State private var selected: Script?
    @State private var deleting: Script?
    @State private var importing = false
    private var filtered: [Script] {
        scripts.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.text.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                if search.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("ВАШИ СЛОВА. ВАШ ГОЛОС.").font(.caption2.weight(.bold)).tracking(1.8).foregroundStyle(Style.green)
                            Text("Говорите свободно").font(.system(size: 29, weight: .bold, design: .rounded))
                            Text("Подготовьте текст. Включите камеру.\nРасскажите свою историю.").foregroundStyle(.secondary).font(.subheadline)
                            WideButton(title: "Новый текст", icon: "plus") { create() }
                        }.padding(.vertical, 12)
                    }.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 10, trailing: 4))
                }
                Section("Сценарии · \(filtered.count)") {
                    if filtered.isEmpty {
                        ContentUnavailableView(search.isEmpty ? "Здесь будут ваши тексты" : "Ничего не найдено",
                                               systemImage: "text.page", description: Text(search.isEmpty ? "Создайте сценарий или импортируйте .txt." : "Попробуйте другое слово."))
                    }
                    ForEach(filtered) { script in
                        Button { selected = script } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "text.alignleft").font(.title3).foregroundStyle(Style.green)
                                    .frame(width: 44, height: 52).background(Style.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(script.title.isEmpty ? "Без названия" : script.title).font(.headline).foregroundStyle(.primary).lineLimit(1)
                                    Text(script.text.isEmpty ? "Добавьте текст для записи" : script.text.replacingOccurrences(of: "\n", with: " "))
                                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                                    Text(script.updatedAt, format: .dateTime.day().month(.abbreviated)).font(.caption).foregroundStyle(.tertiary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                            }.padding(.vertical, 6)
                        }
                        .swipeActions {
                            Button("Удалить", role: .destructive) { deleting = script }
                            Button("Копия") { duplicate(script) }.tint(Style.green)
                        }
                        .contextMenu {
                            Button("Дублировать", systemImage: "doc.on.doc") { duplicate(script) }
                            Button("Удалить", systemImage: "trash", role: .destructive) { deleting = script }
                        }
                    }
                }
            }
            .navigationTitle("Суфлёр")
            .searchable(text: $search, prompt: "Название или фрагмент текста")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Импорт .txt", systemImage: "square.and.arrow.down") { importing = true }
                }
            }
            .navigationDestination(item: $selected) { script in EditorView(script: script) }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText]) { result in importText(result) }
            .confirmationDialog("Удалить текст?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Удалить текст", role: .destructive) {
                    if let deleting { library.context.delete(deleting); library.save() }; deleting = nil
                }
            } message: { Text("Записанные дубли останутся в библиотеке.") }
        }
    }

    private func create() {
        let script = Script(); library.context.insert(script)
        if library.save() { selected = script }
    }

    private func duplicate(_ script: Script) {
        let copy = Script(title: script.title + " — копия", text: script.text)
        library.context.insert(copy)
        if library.save() { selected = copy }
    }

    private func importText(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard url.pathExtension.lowercased() == "txt" else { throw CameraFailure.message("Выберите текстовый файл с расширением .txt.") }
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 2 * 1_024 * 1_024 else { throw CameraFailure.message("Файл слишком большой. Выберите текст до 2 МБ.") }
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
                throw CameraFailure.message("Не удалось прочитать текст. Сохраните файл в UTF-8.")
            }
            let script = Script(title: url.deletingPathExtension().lastPathComponent, text: text)
            library.context.insert(script)
            if library.save() { selected = script }
        } catch { library.errorMessage = error.localizedDescription }
    }
}

