import SwiftUI
import SwiftData
import AVKit

struct TakesView: View {
    @EnvironmentObject private var library: LibraryStore
    @Query(sort: \Take.createdAt, order: .reverse) private var takes: [Take]
    @State private var deleting: Take?
    var body: some View {
        NavigationStack {
            List {
                if library.recovering { HStack { ProgressView(); Text("Проверяем сохранённые дубли…") }.font(.subheadline) }
                ForEach(takes) { take in
                    NavigationLink { TakeDetailView(take: take) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: take.status == "ready" ? "play.fill" : "exclamationmark.triangle")
                                .foregroundStyle(take.status == "ready" ? Style.green : .orange)
                                .frame(width: 48, height: 64).background(Style.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 6) {
                                Text(take.title).font(.headline).lineLimit(2)
                                Text(take.createdAt, format: .dateTime.day().month().hour().minute()).font(.caption).foregroundStyle(.secondary)
                                Text(take.status == "ready" ? "\(Style.duration(take.duration)) · \(take.savedToPhotos ? "Сохранено в Фото" : "На этом iPhone")" : "Требует внимания")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 5)
                    }
                    .disabled(library.recovering)
                    .swipeActions { Button("Удалить", role: .destructive) { deleting = take }.disabled(library.recovering) }
                }
            }
            .overlay {
                if takes.isEmpty && !library.recovering {
                    ContentUnavailableView("Первый дубль впереди", systemImage: "video", description: Text("Откройте текст и запишите видео. Все дубли появятся здесь."))
                }
            }
            .navigationTitle("Дубли")
            .confirmationDialog("Удалить дубль с iPhone?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Удалить дубль", role: .destructive) { if let deleting { library.deleteTake(deleting) }; deleting = nil }
            } message: { Text("Это удалит оригинал внутри приложения. Копия, уже сохранённая в «Фото», останется.") }
        }
    }
}

struct TakeDetailView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var take: Take
    var onRetake: (() -> Void)?
    @State private var player: AVPlayer?
    @State private var exporting = false
    @State private var exportMessage: String?
    private var url: URL { library.files.movieURL(for: take.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if take.status == "ready" {
                    VideoPlayer(player: player).aspectRatio(9 / 16, contentMode: .fit)
                        .frame(maxHeight: 420).clipShape(RoundedRectangle(cornerRadius: 20))
                } else {
                    ContentUnavailableView("Дубль не завершён", systemImage: "video.slash", description: Text(take.note ?? "Файл пока недоступен."))
                }
                HStack {
                    Label(take.status == "ready" ? Style.duration(take.duration) : "Незавершённая запись", systemImage: "clock")
                    Spacer()
                    if take.savedToPhotos { Label("В «Фото»", systemImage: "checkmark.circle.fill").foregroundStyle(Style.green) }
                }.font(.caption).foregroundStyle(.secondary)
                if let note = take.note, take.status == "ready" {
                    Label(note, systemImage: "info.circle").font(.subheadline).foregroundStyle(.secondary)
                }
                if take.status == "ready" {
                    WideButton(title: exporting ? "Сохраняем…" : (take.savedToPhotos ? "Ещё раз сохранить в «Фото»" : "Сохранить в «Фото»"), icon: "square.and.arrow.down") { export() }
                        .disabled(exporting)
                }
                if FileManager.default.fileExists(atPath: url.path) {
                    ShareLink(item: url) {
                        Label("Поделиться видео", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity).padding(.vertical, 10)
                    }.buttonStyle(.bordered).disabled(exporting)
                }
                if let onRetake {
                    Button { player?.pause(); player = nil; onRetake() } label: {
                        Label("Записать ещё дубль", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity).padding(.vertical, 10)
                    }.buttonStyle(.bordered).disabled(exporting)
                }
                Text("Оригинал хранится внутри приложения. Сохраните важные видео в «Фото» или «Файлы» перед удалением приложения.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(20)
        }
        .navigationTitle(take.title).navigationBarTitleDisplayMode(.inline)
        .task(id: take.id) {
            if take.status == "ready" {
                do {
                    try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
                    try AVAudioSession.sharedInstance().setActive(true)
                    player = AVPlayer(url: url)
                } catch { exportMessage = "Не удалось включить звук: \(error.localizedDescription)" }
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { player?.pause() } }
        .onDisappear { player?.pause(); player = nil }
        .alert("Сохранение видео", isPresented: Binding(get: { exportMessage != nil }, set: { if !$0 { exportMessage = nil } })) {
            Button("Понятно", role: .cancel) { exportMessage = nil }
            Button("Настройки iPhone") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
        } message: { Text(exportMessage ?? "") }
    }

    private func export() {
        guard !exporting else { return }
        exporting = true; player?.pause()
        Task {
            defer { exporting = false }
            do {
                try await PhotoExporter.save(url)
                take.savedToPhotos = true
                library.save()
                exportMessage = "Видео сохранено в «Фото». Оригинал также остался в приложении."
            } catch { exportMessage = "\(error.localizedDescription)\n\nОригинал остался в приложении. Можно повторить сохранение." }
        }
    }
}
