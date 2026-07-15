import BoomstreamAPI
import BoomstreamOffline
import BoomstreamPlayer
import SwiftUI

/// Вкладка «Медиа»: плеер сверху, три горизонтальные ленты листингов,
/// offline-секция под выбранным медиа.
struct MediaTabView: View {
    @ObservedObject var vm: MainViewModel
    @StateObject private var proxy = BoomstreamPlayerProxy()

    var body: some View {
        if vm.apiKeyMissing && vm.selectedMediaCode == nil {
            NoApiKeyScreen()
        } else {
            // Плеер вне ScrollView: в fullscreen растягивается на весь экран,
            // identity сохраняется (без перезапуска плейбека).
            VStack(spacing: 0) {
                playerArea
                if !vm.isFullScreen {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            header
                            if vm.apiKeyMissing {
                                Text("Листинги требуют API-ключ (BOOMSTREAM_API_KEY в Config/Local.xcconfig); играет demo-код.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            if vm.listLoading && vm.mediaList.isEmpty {
                                HStack { Spacer(); ProgressView(); Spacer() }
                            }
                            if let error = vm.listError {
                                Text(error).font(.caption).foregroundColor(.red)
                            }
                            MediaPickerSection(label: "Выберите видео", items: vm.mediaList, vm: vm)
                            MediaPickerSection(label: "Трансляции", items: vm.liveList, vm: vm)
                            MediaPickerSection(label: "Плейлисты", items: vm.playlistList, vm: vm)
                            OfflineDownloadSection(vm: vm)
                        }
                        .padding()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var playerArea: some View {
        if let code = vm.selectedMediaCode {
            BoomstreamPlayerView(
                mediaCode: code,
                proxy: proxy,
                offlineCache: AppEnvironment.offline,
                onFullScreenChanged: { vm.handleFullScreenChanged($0) }
            )
            // В fullscreen контейнеру задаётся пропорция экрана (не nil — SwiftUI
            // трактует nil как ideal-size и схлопывает representable), видео внутри
            // AVPlayerLayer сам вписывает по aspect
            .aspectRatio(vm.isFullScreen ? screenAspectRatio() : 16 / 9, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: vm.isFullScreen ? .infinity : nil)
            .background(Color.black)
            .ignoresSafeArea(edges: vm.isFullScreen ? .all : [])
            .onReceive(proxy.$controller) { vm.activeController = $0 }
        } else {
            ZStack {
                Color.black
                ProgressView().tint(.white)
            }
            .aspectRatio(16 / 9, contentMode: .fit)
        }
    }

    @ViewBuilder
    private var header: some View {
        if let code = vm.selectedMediaCode {
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.mediaTitle ?? code).font(.headline)
                if let description = vm.mediaDescription {
                    Text(description).font(.subheadline).foregroundColor(.secondary)
                }
            }
        }
    }
}

struct NoApiKeyScreen: View {
    var body: some View {
        VStack {
            Spacer()
            Text("API-ключ не задан.\nУкажите BOOMSTREAM_API_KEY в Config/Local.xcconfig.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding()
            Spacer()
        }
    }
}

/// Горизонтальная лента листинга; рендерится только при непустом списке.
struct MediaPickerSection: View {
    let label: String
    let items: [ContentItem]
    @ObservedObject var vm: MainViewModel

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(label).font(.headline)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(items) { item in
                            MediaCard(item: item, isSelected: vm.selectedMediaCode == item.code) {
                                vm.selectMedia(item.code)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Карточка медиа: постер 16:9, title 2 строки, длительность.
struct MediaCard: View {
    let item: ContentItem
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                AsyncImage(url: item.posterURL) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    ZStack {
                        Color.gray.opacity(0.25)
                        Image(systemName: "play.rectangle").foregroundColor(.secondary)
                    }
                }
                .frame(width: 140, height: 79)
                .clipped()
                .cornerRadius(6)

                Text(item.title.isEmpty ? item.code : item.title)
                    .font(.caption)
                    .fontWeight(isSelected ? .bold : .regular)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundColor(.primary)
                if item.duration > 0 {
                    Text(timeString(seconds: Double(item.duration)))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(6)
            .frame(width: 152, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground)))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Offline-секция под выбранным медиа — state machine `DownloadState`.
struct OfflineDownloadSection: View {
    @ObservedObject var vm: MainViewModel

    var body: some View {
        if vm.selectedMediaCode != nil {
            VStack(alignment: .leading, spacing: 8) {
                switch vm.selectedDownloadState {
                case nil:
                    Button("Скачать для просмотра офлайн") { vm.startDownload() }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)

                case .queued:
                    ProgressView().frame(maxWidth: .infinity)
                    Text("Загрузка…").font(.caption).foregroundColor(.secondary)
                    Button("Отменить загрузку") { vm.cancelDownload() }
                        .buttonStyle(.bordered)

                case .inProgress(_, let percent, _):
                    ProgressView(value: percent)
                    Text("\(Int(percent * 100))%").font(.caption).foregroundColor(.secondary)
                    Button("Отменить загрузку") { vm.cancelDownload() }
                        .buttonStyle(.bordered)

                case .paused(_, let percent):
                    ProgressView(value: percent)
                    Text("Пауза · \(Int(percent * 100))%").font(.caption).foregroundColor(.secondary)
                    Button("Отменить загрузку") { vm.cancelDownload() }
                        .buttonStyle(.bordered)

                case .completed:
                    HStack {
                        Label("Загружено", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Spacer()
                        Button(role: .destructive) { vm.deleteDownload() } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }

                case .failed(_, let error):
                    Text("Ошибка загрузки")
                        .font(.subheadline).foregroundColor(.red)
                    Text(error.localizedDescription)
                        .font(.caption2).foregroundColor(.secondary)
                    Button("Скачать снова") { vm.startDownload() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(.top, 4)
        }
    }
}
