import SwiftUI
import UIKit

struct RecordingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: RecordingModel
    @State private var showingSettings = false

    init(script: Script, library: LibraryStore) {
        _model = StateObject(wrappedValue: RecordingModel(script: script, library: library))
    }

    var body: some View {
        ZStack {
            if let take = model.completedTake, model.phase == .review {
                NavigationStack {
                    TakeDetailView(take: take, onRetake: { model.retry() })
                        .environmentObject(model.library)
                        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Готово") { dismiss() } } }
                }
            } else {
                cameraScreen
            }
        }
        .interactiveDismissDisabled(!model.canDismiss)
        .task { model.prepare() }
        .onDisappear { model.close(); model.library.save() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.enterForeground() }
            else if phase == .background || (phase == .inactive && model.phase != .preparing) { model.leaveForeground() }
        }
        .alert("Запись", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            if model.needsSettings {
                Button("Настройки iPhone") { openSettings() }
            }
            Button("Понятно", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .sheet(isPresented: $showingSettings, onDismiss: { model.library.save() }) {
            PromptSettingsView(settings: model.library.settings)
                .environmentObject(model.library)
                .presentationDetents([.large])
        }
    }

    private var cameraScreen: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = min(width * 16 / 9, geometry.size.height)
            let topInset = geometry.safeAreaInsets.top

            ZStack(alignment: .top) {
                CameraPreview(session: model.camera.session, front: model.frontCamera)
                if model.phase != .failed {
                    PrompterView(text: model.text, fontSize: model.library.settings.fontSize,
                                 spacing: model.library.settings.lineSpacing, speed: model.library.settings.speed,
                                 resetToken: model.resetToken, running: $model.scrolling)
                    .frame(width: width * model.library.settings.widthFraction, height: min(height * 0.5, 320))
                    .background(.black.opacity(model.library.settings.backgroundOpacity), in: RoundedRectangle(cornerRadius: 18))
                    .overlay(alignment: .topLeading) {
                        Capsule().fill(.white.opacity(0.8)).frame(width: 3, height: 24).padding(.top, 25).padding(.leading, 7).allowsHitTesting(false)
                    }
                    .padding(.top, topInset + 32)
                    .allowsHitTesting(model.phase == .ready || model.phase == .recording)
                }
                if case .countdown(let seconds) = model.phase {
                    VStack { Spacer(); Text("\(seconds)").font(.system(size: 92, weight: .bold, design: .rounded))
                        .shadow(radius: 20); Spacer() }.frame(maxWidth: .infinity).background(.black.opacity(0.25))
                }
                if model.phase == .preparing || model.phase == .starting || model.phase == .finishing {
                    VStack(spacing: 12) {
                        ProgressView().tint(.white)
                        Text(model.phase == .finishing ? "Сохраняем дубль…" : "Готовим камеру…").font(.subheadline)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).background(.black.opacity(0.7))
                }
                if model.phase == .failed {
                    VStack(spacing: 18) {
                        Image(systemName: "video.slash").font(.largeTitle)
                        Text(model.interruptionMessage ?? "Камера пока недоступна").multilineTextAlignment(.center)
                        Button("Повторить") { model.retry() }.buttonStyle(.borderedProminent).tint(Style.green)
                        if model.needsSettings { Button("Настройки iPhone") { openSettings() } }
                    }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(Style.cameraBackground)
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .overlay(alignment: .bottom) {
                controlPanel.padding(.bottom, geometry.safeAreaInsets.bottom + 2)
            }
        }
        .ignoresSafeArea()
        .foregroundStyle(.white)
        .background(Style.cameraBackground.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private var controlPanel: some View {
        VStack(spacing: 8) {
            HStack {
                chromeButton("Закрыть", icon: "xmark") { dismiss() }.disabled(!model.canDismiss)
                Spacer(minLength: 8)
                HStack(spacing: 7) {
                    Circle().fill(model.phase == .recording ? .red : .white.opacity(0.4)).frame(width: 6, height: 6)
                    if model.phase == .recording {
                        TimelineView(.periodic(from: .now, by: 1)) { timeline in
                            Text("Запись  \(Style.duration(timeline.date.timeIntervalSince(model.startedAt ?? timeline.date)))")
                                .monospacedDigit().font(.caption.weight(.medium))
                        }
                    } else { Text(statusLabel).font(.caption).foregroundStyle(.white.opacity(0.85)) }
                }
                Spacer(minLength: 8)
                chromeButton("Настройки чтения", icon: "slider.horizontal.3") {
                    model.scrolling = false; showingSettings = true
                }.disabled(model.phase != .ready || model.switchingCamera)
            }.padding(.horizontal, 24)
            HStack(spacing: 10) {
                Image(systemName: "tortoise").font(.caption2).accessibilityHidden(true)
                Slider(value: Binding(get: { model.library.settings.speed }, set: { model.library.settings.speed = $0 }), in: 10...120, step: 1)
                    .tint(.white).accessibilityLabel("Скорость прокрутки")
                    .accessibilityValue("\(Int(model.library.settings.speed)) пунктов в секунду")
                    .disabled(model.phase != .ready && model.phase != .recording)
                Image(systemName: "hare").font(.caption2).accessibilityHidden(true)
            }
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 28)
            HStack {
                HStack(spacing: 22) {
                    secondaryButton(icon: "backward.end", label: "В начало") { model.scrolling = false; model.resetToken += 1 }
                        .disabled(model.phase != .ready && model.phase != .recording)
                    secondaryButton(icon: model.scrolling ? "pause.fill" : "play.fill", label: model.scrolling ? "Пауза" : "Пуск текста") {
                        model.scrolling.toggle()
                    }.disabled((model.phase != .ready && model.phase != .recording) || model.switchingCamera)
                }
                Spacer()
                recordButton
                Spacer()
                HStack(spacing: 22) {
                    secondaryButton(icon: "arrow.triangle.2.circlepath.camera", label: "Камера") { model.switchCamera() }
                        .disabled(model.phase != .ready || model.switchingCamera)
                    secondaryButton(icon: "flip.horizontal", label: "Зеркально", active: model.library.settings.mirrorVideo) {
                        model.library.settings.mirrorVideo.toggle()
                    }.disabled(!model.frontCamera || model.phase != .ready)
                }
            }.padding(.horizontal, 24)
        }
        .padding(.top, 10).padding(.bottom, 20)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24, style: .continuous)
                .fill(Style.cameraBackground)
                .padding(.top, -40)
                .allowsHitTesting(false)
        }
    }

    private func chromeButton(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.subheadline.weight(.semibold)).frame(width: 30, height: 30)
        }.labelStyle(.iconOnly).accessibilityLabel(label)
    }

    private func secondaryButton(icon: String, label: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) { Image(systemName: icon).font(.callout); Text(label).font(.system(size: 9)) }
                .frame(width: 54)
                .foregroundStyle(active ? Style.green : .white)
        }
    }

    private var recordButton: some View {
        Button {
            if case .countdown = model.phase { model.cancelCountdown() }
            else if model.phase == .recording { model.stop() }
            else { model.start() }
        } label: {
            ZStack {
                Circle().stroke(.white.opacity(0.9), lineWidth: 3).frame(width: 64, height: 64)
                if model.phase == .recording {
                    RoundedRectangle(cornerRadius: 7).fill(.red).frame(width: 27, height: 27)
                } else if case .countdown = model.phase {
                    Image(systemName: "xmark").font(.title2.bold())
                } else { Circle().fill(.red).frame(width: 52, height: 52) }
            }.frame(width: 74, height: 74)
        }
        .accessibilityLabel(recordLabel)
        .disabled(!recordButtonEnabled)
    }

    private var recordButtonEnabled: Bool {
        guard !model.switchingCamera, model.foreground else { return false }
        return switch model.phase { case .ready, .recording, .countdown: true; default: false }
    }
    private var recordLabel: String {
        switch model.phase { case .recording: "Остановить запись"; case .countdown: "Отменить отсчёт"; default: "Начать запись" }
    }
    private var statusLabel: String {
        switch model.phase {
        case .ready: model.scrolling ? "Репетиция · видео не записывается" : "Готово к записи"
        case .countdown: "Приготовьтесь · можно отменить отсчёт"
        case .finishing: "Дождитесь сохранения файла"
        case .failed: "Запись остановлена"
        default: "Камера и встроенный микрофон"
        }
    }
    private func openSettings() { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
}
