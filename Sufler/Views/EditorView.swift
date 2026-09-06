import SwiftUI

struct EditorView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var script: Script
    @State private var showingCamera = false
    @State private var autosave: Task<Void, Never>?
    @FocusState private var editing: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Название сценария", text: $script.title)
                    .font(.title2.bold()).accessibilityLabel("Название сценария")
                HStack {
                    Text("\(script.text.split(whereSeparator: { $0.isWhitespace }).count) слов").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    PasteButton(payloadType: String.self) { strings in
                        let pasted = strings.joined(separator: "\n")
                        if !script.text.isEmpty { script.text += "\n\n" }
                        script.text += pasted
                    }.labelStyle(.titleAndIcon).buttonBorderShape(.capsule)
                }
            }.padding(20)
            Divider()
            TextEditor(text: $script.text)
                .font(.system(size: 20)).lineSpacing(7).padding(.horizontal, 14)
                .focused($editing).accessibilityLabel("Текст сценария")
                .overlay(alignment: .topLeading) {
                    if script.text.isEmpty {
                        Text("Напишите текст или вставьте готовый сценарий…")
                            .foregroundStyle(.tertiary).padding(.horizontal, 20).padding(.top, 10).allowsHitTesting(false)
                    }
                }
        }
        .background(.background)
        .navigationTitle("Сценарий").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Готово") { editing = false } }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                WideButton(title: "К записи", icon: "video.fill") {
                    editing = false
                    autosave?.cancel()
                    if library.save() { showingCamera = true }
                }
                .disabled(script.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || library.recovering)
                Text(library.recovering ? "Проверяем сохранённые дубли…" : "Текст виден только вам — в видео он не попадёт")
                    .font(.caption2).foregroundStyle(.secondary)
            }.padding(.horizontal, 20).padding(.vertical, 12).background(.bar)
        }
        .onChange(of: script.text) { _, _ in scheduleSave() }
        .onChange(of: script.title) { _, _ in scheduleSave() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { autosave?.cancel(); library.save() } }
        .onDisappear { autosave?.cancel(); library.save() }
        .fullScreenCover(isPresented: $showingCamera) { RecordingView(script: script, library: library) }
    }

    private func scheduleSave() {
        script.updatedAt = Date()
        autosave?.cancel()
        autosave = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            library.save()
        }
    }
}

