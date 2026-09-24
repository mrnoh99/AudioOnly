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
        .commands {
            // iPad 하드웨어 키보드: ⌘ 키를 누르고 있으면 단축키 목록이 보인다.
            CommandMenu("이동") {
                ForEach(AppTab.allCases) { tab in
                    Button(tab.title) { model.selectedTab = tab }
                        .keyboardShortcut(tab.shortcut, modifiers: .command)
                }
            }
        }
    }
}

extension AppTab: CaseIterable, Identifiable {
    static var allCases: [AppTab] { [.url, .playlist, .files, .library, .settings] }

    var id: Self { self }

    var title: String {
        switch self {
        case .url: return "YouTube 주소"
        case .playlist: return "재생목록"
        case .files: return "다운로드한 파일"
        case .library: return "보관함"
        case .settings: return "설정"
        }
    }

    var shortTitle: String {
        switch self {
        case .url: return "주소"
        case .files: return "파일"
        default: return title
        }
    }

    var systemImage: String {
        switch self {
        case .url: return "link"
        case .playlist: return "list.bullet.rectangle"
        case .files: return "film"
        case .library: return "music.note.list"
        case .settings: return "gearshape"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .url: return "1"
        case .playlist: return "2"
        case .files: return "3"
        case .library: return "4"
        case .settings: return "5"
        }
    }

    /// 추출 입력 화면(옆에 작업 패널을 함께 보여 줄 화면)
    var isInputScreen: Bool { self == .url || self == .playlist || self == .files }
}

/// iPad 전체 화면(regular)에서는 사이드바 + 작업 패널, 좁은 화면(Split View/Slide Over/iPhone)에서는 탭 막대
struct RootView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @EnvironmentObject private var player: AudioPlayer

    var body: some View {
        Group {
            if sizeClass == .compact {
                CompactRootView()
            } else {
                SplitRootView()
            }
        }
        // 음악 앱처럼 미니 플레이어를 누르면 전체 화면 '지금 재생 중'
        .fullScreenCover(isPresented: $player.showNowPlaying) {
            NowPlayingView()
                .environmentObject(player)
        }
    }
}

struct CompactRootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView(selection: $model.selectedTab) {
            ForEach(AppTab.allCases) { tab in
                ScreenView(tab: tab)
                    .tabItem { Label(tab.shortTitle, systemImage: tab.systemImage) }
                    .tag(tab)
                    .badge(tab == .library ? model.activeJobCount : 0)
            }
        }
    }
}

struct SplitRootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private var selection: Binding<AppTab?> {
        Binding(
            get: { model.selectedTab },
            set: { if let tab = $0 { model.selectedTab = tab } }
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: selection) {
                Section("추출") {
                    ForEach([AppTab.url, .playlist, .files]) { tab in
                        NavigationLink(value: tab) {
                            Label(tab.title, systemImage: tab.systemImage)
                        }
                    }
                }
                Section {
                    NavigationLink(value: AppTab.library) {
                        Label(AppTab.library.title, systemImage: AppTab.library.systemImage)
                    }
                    .badge(model.activeJobCount)
                    NavigationLink(value: AppTab.settings) {
                        Label(AppTab.settings.title, systemImage: AppTab.settings.systemImage)
                    }
                }
                if model.activeJobCount > 0 {
                    Section("진행 중") {
                        ForEach(model.jobs.filter { !$0.status.isFinished }.prefix(5)) { job in
                            SidebarJobRow(job: job)
                        }
                    }
                }
            }
            .navigationTitle("AudioOnly")
        } detail: {
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    ScreenView(tab: model.selectedTab)
                        .frame(maxWidth: .infinity)
                    // 가로 화면처럼 넓을 때는 작업 진행 상황을 옆에 계속 보여 준다.
                    if model.selectedTab.isInputScreen && proxy.size.width >= 820 {
                        Divider()
                        JobsPanelView()
                            .frame(width: min(380, proxy.size.width * 0.4))
                    }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}

struct ScreenView: View {
    let tab: AppTab

    var body: some View {
        content
            // 어느 화면에서든 아래쪽에 미니 플레이어
            .safeAreaInset(edge: .bottom, spacing: 0) {
                MiniPlayerBar()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .url: URLInputView()
        case .playlist: PlaylistInputView()
        case .files: LocalFilesView()
        case .library: LibraryView()
        case .settings: SettingsView()
        }
    }
}

struct SidebarJobRow: View {
    @ObservedObject var job: Job

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(job.title).font(.caption).lineLimit(1)
            if let progress = job.progress, job.status.isActive {
                ProgressView(value: progress)
            } else {
                Text(job.statusText).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
