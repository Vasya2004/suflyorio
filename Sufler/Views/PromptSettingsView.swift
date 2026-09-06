import SwiftUI

struct PromptSettingsView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @Bindable var settings: PromptSettings

    var body: some View {
        NavigationStack {
            Form {
                Section("Предпросмотр") {
                    Text("Говорите спокойно.\nВаш текст перед глазами.")
                        .font(.system(size: settings.fontSize, weight: .semibold)).lineSpacing(settings.lineSpacing)
                        .foregroundStyle(.white).padding(18).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.black.opacity(settings.backgroundOpacity), in: RoundedRectangle(cornerRadius: 16))
                }
                Section("Удобное чтение") {
                    settingSlider("Размер текста", value: $settings.fontSize, range: 22...56, suffix: " пт")
                    settingSlider("Межстрочный интервал", value: $settings.lineSpacing, range: 2...22, suffix: " пт")
                    VStack(alignment: .leading) {
                        Text("Ширина текста · \(Int(settings.widthFraction * 100)) %")
                        Slider(value: $settings.widthFraction, in: 0.65...0.98, step: 0.01).accessibilityLabel("Ширина текста")
                    }
                    VStack(alignment: .leading) {
                        Text("Затемнение под текстом · \(Int(settings.backgroundOpacity * 100)) %")
                        Slider(value: $settings.backgroundOpacity, in: 0.2...0.95, step: 0.05).accessibilityLabel("Затемнение под текстом")
                    }
                    settingSlider("Скорость", value: $settings.speed, range: 10...120, suffix: " пт/с")
                }
                Section {
                    Picker("Отсчёт перед записью", selection: $settings.countdown) {
                        Text("Без задержки").tag(0); Text("3 секунды").tag(3); Text("5 секунд").tag(5)
                    }
                    Toggle("Зеркальное селфи-видео", isOn: $settings.mirrorVideo)
                } header: { Text("Запись") } footer: {
                    Text("Предпросмотр фронтальной камеры всегда зеркальный. Переключатель меняет только сохранённое селфи-видео. Текст суфлёра в запись не попадает.")
                }
            }
            .navigationTitle("Настройки чтения").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { if library.save() { dismiss() } } } }
            .onDisappear { library.save() }
        }.tint(Style.green)
    }

    private func settingSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String) -> some View {
        VStack(alignment: .leading) {
            Text("\(title) · \(Int(value.wrappedValue))\(suffix)")
            Slider(value: value, in: range, step: 1).accessibilityLabel(title)
        }
    }
}

