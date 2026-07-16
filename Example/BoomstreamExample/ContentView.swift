import SwiftUI

/// Двухвкладочная структура («Медиа» / «Player API»). Кастомный переключатель
/// вместо TabView: неактивная вкладка уничтожается, поэтому одновременно живёт
/// только один плеер.
struct ContentView: View {
    @StateObject private var vm = MainViewModel()
    // compact по вертикали = landscape на iPhone
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    // "-tab2" — launch-хук для UI-тестов/автоматизации (открыть Player API сразу)
    @State private var selectedTab = ProcessInfo.processInfo.arguments.contains("-tab2") ? 1 : 0

    var body: some View {
        VStack(spacing: 0) {
            if !vm.isFullScreen {
                Picker("", selection: $selectedTab) {
                    Text("Медиа").tag(0)
                    Text("Player API").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            switch selectedTab {
            case 0: MediaTabView(vm: vm)
            default: PlayerAPITabView(vm: vm)
            }
        }
        .statusBarHidden(vm.isFullScreen)
        .animation(.easeInOut(duration: 0.2), value: vm.isFullScreen)
        .onChange(of: verticalSizeClass) { newValue in
            vm.handleOrientation(isLandscape: newValue == .compact)
        }
        .onAppear {
            vm.handleOrientation(isLandscape: verticalSizeClass == .compact)
        }
    }
}
