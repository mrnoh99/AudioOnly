import SwiftUI

@main
struct AudioOnlyiOSApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var player = AudioPlayer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(player)
                .onOpenURL { model.handleOpenURL($0) }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView(selection: $model.selectedTab) {
            URLInputView()
                .tabItem { Label("주소", systemImage: "link") }
                .tag(AppTab.url)
            PlaylistInputView()
                .tabItem { Label("재생목록", systemImage: "list.bullet.rectangle") }
                .tag(AppTab.playlist)
            LocalFilesView()
                .tabItem { Label("파일", systemImage: "film") }
                .tag(AppTab.files)
            LibraryView()
                .tabItem { Label("보관함", systemImage: "music.note.list") }
                .tag(AppTab.library)
                .badge(model.activeJobCount)
            SettingsView()
                .tabItem { Label("설정", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
    }
}
