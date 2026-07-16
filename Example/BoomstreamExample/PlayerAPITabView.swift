import BoomstreamAPI
import BoomstreamPlayer
import SwiftUI

/// Вкладка «Player API»: кастомные вызовы контроллера, прогресс, 70%-триггер,
/// event log, fullscreen-пейн.
struct PlayerAPITabView: View {
    @ObservedObject var vm: MainViewModel
    @StateObject private var proxy = BoomstreamPlayerProxy()
    @State private var progress = PlaybackProgress(position: 0, duration: 0, bufferedPosition: 0)
    @State private var eventLog: [String] = []
    @State private var reached70 = false
    @State private var volume = 1.0
    @State private var lastLoggedProgressDecade = -1

    var body: some View {
        if let code = vm.selectedMediaCode {
            content(code: code)
        } else {
            VStack {
                Spacer()
                Text("Выберите медиа на вкладке «Медиа»")
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
    }

    private func content(code: String) -> some View {
        VStack(spacing: 0) {
            // Единственная точка с плеером: модификаторы меняются значениями (не ветками),
            // идентичность view сохраняется — плейбек не перезапускается при fullscreen.
            BoomstreamPlayerView(
                mediaCode: code,
                proxy: proxy,
                onFullScreenChanged: { vm.handleFullScreenChanged($0) }
            )
            .aspectRatio(vm.isFullScreen ? vm.fullscreenAspectRatio : 16 / 9, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: vm.isFullScreen ? .infinity : nil)
            .background(Color.black)
            .ignoresSafeArea(edges: vm.isFullScreen ? .all : [])
            .onReceive(proxy.$controller) { vm.activeController = $0 }

            if !vm.isFullScreen {
                controlsPane
            }
        }
        .task(id: code) { await observeProgress() }
        .task(id: code) { await observeEvents() }
        .onChange(of: code) { _ in
            resetPerMediaState()
        }
    }

    private var controlsPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                progressSection
                if reached70 {
                    Text("✅ Достигнуто 70% видео — клиентский триггер сработал бы здесь")
                        .font(.callout)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.15)))
                }
                controlsSection
                eventLogSection
            }
            .padding()
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Прогресс").font(.headline)
            ProgressView(value: progress.fraction)
            Text("\(timeString(seconds: progress.position)) / \(timeString(seconds: progress.duration)) (\(Int(progress.fraction * 100))%)")
                .font(.caption.monospaced())
                .foregroundColor(.secondary)
        }
    }

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Управление").font(.headline)
            HStack(spacing: 10) {
                Button("▶ Play") { proxy.controller?.play() }
                Button("⏸ Pause") { proxy.controller?.pause() }
            }
            HStack(spacing: 10) {
                Button("« −10s") {
                    guard let controller = proxy.controller else { return }
                    controller.seek(to: max(0, controller.currentPosition - 10))
                }
                Button("+10s »") {
                    guard let controller = proxy.controller else { return }
                    controller.seek(to: controller.currentPosition + 10)
                }
                Button("50%") { proxy.controller?.seek(toPercent: 0.5) }
            }
            HStack(spacing: 10) {
                Button("🔇 Mute") { proxy.controller?.mute() }
                Button("🔊 Unmute") { proxy.controller?.unmute() }
                Button("⛶ FullScr") { proxy.controller?.toggleFullScreen() }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Громкость: \(Int(volume * 100))%").font(.subheadline)
                Slider(value: $volume, in: 0...1) { _ in
                    proxy.controller?.setVolume(Float(volume))
                }
            }
        }
        .buttonStyle(.bordered)
    }

    private var eventLogSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("События (последние 5)").font(.headline)
            if eventLog.isEmpty {
                Text("— нажмите Play, чтобы начать воспроизведение —")
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(eventLog.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.caption.monospaced())
                }
            }
        }
    }

    // MARK: - Streams

    private func observeProgress() async {
        guard let controller = await waitForController() else { return }
        for await snapshot in controller.progress {
            progress = snapshot
            if snapshot.fraction >= 0.7 { reached70 = true }
        }
    }

    private func observeEvents() async {
        guard let controller = await waitForController() else { return }
        for await event in controller.events {
            switch event {
            case .loaded:
                log("Loaded duration=\(timeString(seconds: controller.duration))")
            case .playing:
                log("Playing pos=\(timeString(seconds: controller.currentPosition))")
            case .paused:
                log("Paused pos=\(timeString(seconds: controller.currentPosition))")
            case .ended:
                log("Ended")
            case .progress(let snapshot):
                // без троттлинга лог был бы целиком из Progress-строк (2 события/сек)
                let decade = Int(snapshot.fraction * 10)
                if decade != lastLoggedProgressDecade {
                    lastLoggedProgressDecade = decade
                    log("Progress \(Int(snapshot.fraction * 100))%")
                }
            case .seeked(let position):
                log("Seeked pos=\(timeString(seconds: position))")
                if progress.duration > 0, position / progress.duration < 0.7 {
                    reached70 = false
                }
            case .fullScreenChanged(let fullScreen):
                log("FullScreenChanged fs=\(fullScreen)")
            }
        }
    }

    private func waitForController() async -> (any BoomstreamPlayerController)? {
        for _ in 0..<100 where proxy.controller == nil {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return proxy.controller
    }

    private func log(_ line: String) {
        eventLog.insert(line, at: 0)
        if eventLog.count > 5 { eventLog.removeLast(eventLog.count - 5) }
    }

    private func resetPerMediaState() {
        progress = PlaybackProgress(position: 0, duration: 0, bufferedPosition: 0)
        eventLog = []
        reached70 = false
        lastLoggedProgressDecade = -1
    }
}
