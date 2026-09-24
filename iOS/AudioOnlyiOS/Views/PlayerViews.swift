import AVKit
import MediaPlayer
import SwiftUI

// MARK: - 앨범 아트

/// 앨범 아트(없으면 주황 그라데이션 + 음표)
struct ArtworkView: View {
    var image: UIImage?
    var size: CGFloat?
    var cornerRadius: CGFloat = 8

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.69, blue: 0.13), Color(red: 0.94, green: 0.31, blue: 0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "music.note")
                        .resizable()
                        .scaledToFit()
                        .padding((size ?? 200) * 0.28)
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .frame(width: size, height: size)
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// 파일의 앨범 아트를 비동기로 읽어 보여 준다(목록용 작은 썸네일).
struct FileArtworkView: View {
    let url: URL
    var size: CGFloat = 48
    @State private var image: UIImage?

    var body: some View {
        ArtworkView(image: image, size: size, cornerRadius: 6)
            .task(id: url) {
                image = TrackInfoCache.shared.cached(url)?.artwork
                if image == nil {
                    image = await TrackInfoCache.shared.info(for: url).artwork
                }
            }
    }
}

// MARK: - 미니 플레이어

/// 탭 막대 위에 떠 있는 미니 플레이어. 누르면 전체 화면 '지금 재생 중'이 열린다.
struct MiniPlayerBar: View {
    @EnvironmentObject private var player: AudioPlayer

    var body: some View {
        if player.current != nil {
            HStack(spacing: 12) {
                ArtworkView(image: player.info.artwork, size: 44, cornerRadius: 6)
                VStack(alignment: .leading, spacing: 1) {
                    Text(player.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        if player.isSleepTimerActive {
                            Image(systemName: "moon.zzz.fill")
                        }
                        Text(player.subtitle).lineLimit(1)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 44, height: 44)
                }
                Button {
                    player.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title3)
                        .frame(width: 40, height: 44)
                }
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
            .padding(.trailing, 4)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(alignment: .bottom) {
                // 얇은 진행 막대
                GeometryReader { proxy in
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: proxy.size.width * progress, height: 2)
                }
                .frame(height: 2)
                .padding(.horizontal, 14)
            }
            .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
            .contentShape(Rectangle())
            .onTapGesture { player.showNowPlaying = true }
            .gesture(
                DragGesture(minimumDistance: 15).onEnded { value in
                    if value.translation.height < -30 { player.showNowPlaying = true }
                }
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("지금 재생 중: \(player.title)")
        }
    }

    private var progress: CGFloat {
        guard player.duration > 0 else { return 0 }
        return CGFloat(min(max(player.currentTime / player.duration, 0), 1))
    }
}

// MARK: - 지금 재생 중

struct NowPlayingView: View {
    @EnvironmentObject private var player: AudioPlayer
    @Environment(\.dismiss) private var dismiss
    /// iPhone 가로 화면처럼 세로 공간이 좁은 경우
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var scrubTime: TimeInterval?
    @State private var showQueue = false
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let wide = proxy.size.width > proxy.size.height
            ZStack {
                background
                VStack(spacing: 0) {
                    grabber
                    if wide {
                        HStack(spacing: isCompactHeight ? 28 : 48) {
                            artwork(maxSide: min(proxy.size.height * (isCompactHeight ? 0.72 : 0.62), proxy.size.width * 0.42))
                            controls.frame(maxWidth: 460)
                        }
                        .frame(maxHeight: .infinity)
                        .padding(.horizontal, isCompactHeight ? 24 : 48)
                    } else {
                        Spacer(minLength: 12)
                        artwork(maxSide: min(proxy.size.width - 64, proxy.size.height * 0.42, 520))
                        Spacer(minLength: 20)
                        controls
                            .frame(maxWidth: 560)
                            .padding(.horizontal, 28)
                        Spacer(minLength: 12)
                    }
                }
                .padding(.bottom, 12)
            }
            .offset(y: dragOffset)
            .gesture(
                DragGesture()
                    .onChanged { value in dragOffset = max(0, value.translation.height) }
                    .onEnded { value in
                        if value.translation.height > 140 {
                            dismiss()
                        } else {
                            withAnimation(.spring) { dragOffset = 0 }
                        }
                    }
            )
        }
        .foregroundStyle(.white)
        .tint(.white)
        .sheet(isPresented: $showQueue) {
            QueueView()
                .environmentObject(player)
        }
        .onChange(of: player.current) { _, newValue in
            if newValue == nil { dismiss() }
        }
    }

    // 앨범 아트를 흐리게 깐 배경 (음악 앱처럼)
    private var background: some View {
        ZStack {
            Color(red: 0.25, green: 0.12, blue: 0.05)
            if let image = player.info.artwork {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 60)
                    .scaleEffect(1.4)
            } else {
                LinearGradient(
                    colors: [Color(red: 0.95, green: 0.55, blue: 0.15), Color(red: 0.45, green: 0.14, blue: 0.04)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            Color.black.opacity(0.35)
        }
        .ignoresSafeArea()
    }

    private var grabber: some View {
        Button {
            dismiss()
        } label: {
            Capsule()
                .fill(.white.opacity(0.5))
                .frame(width: 40, height: 5)
                .frame(maxWidth: .infinity, minHeight: 28)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("닫기")
    }

    private func artwork(maxSide: CGFloat) -> some View {
        ArtworkView(image: player.info.artwork, size: maxSide, cornerRadius: 14)
            .shadow(color: .black.opacity(0.4), radius: player.isPlaying ? 30 : 12, y: 12)
            // 일시정지하면 앨범 아트가 살짝 작아진다.
            .scaleEffect(player.isPlaying ? 1 : 0.82)
            .animation(.spring(response: 0.45, dampingFraction: 0.72), value: player.isPlaying)
    }

    private var isCompactHeight: Bool { verticalSizeClass == .compact }

    private var controls: some View {
        VStack(spacing: isCompactHeight ? 10 : 22) {
            titleRow
            scrubber
            transport
            // 세로 공간이 좁으면 볼륨은 기기 버튼으로 (음악 앱과 같음)
            if !isCompactHeight {
                volume
            }
            bottomRow
        }
    }

    private var titleRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(player.title)
                    .font(.title3.weight(.bold))
                    .lineLimit(2)
                Text(player.subtitle)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            Spacer()
            Menu {
                if let item = player.current {
                    ShareLink(item: item.url) {
                        Label("공유", systemImage: "square.and.arrow.up")
                    }
                }
                Menu {
                    ForEach(AudioPlayer.speeds, id: \.self) { speed in
                        Button {
                            player.setRate(speed)
                        } label: {
                            if speed == player.rate {
                                Label(speedText(speed), systemImage: "checkmark")
                            } else {
                                Text(speedText(speed))
                            }
                        }
                    }
                } label: {
                    Label("재생 속도 (\(speedText(player.rate)))", systemImage: "gauge.with.dots.needle.67percent")
                }
                Button(role: .destructive) {
                    player.stop()
                } label: {
                    Label("재생 중지", systemImage: "stop.fill")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.headline)
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.15), in: Circle())
            }
        }
    }

    private var scrubber: some View {
        let shown = scrubTime ?? player.currentTime
        let total = max(player.duration, 1)
        return VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { min(shown, total) },
                    set: { scrubTime = $0 }
                ),
                in: 0...total,
                onEditingChanged: { editing in
                    if !editing, let time = scrubTime {
                        player.seek(to: time)
                        scrubTime = nil
                    }
                }
            )
            HStack {
                Text(Self.format(shown))
                Spacer()
                Text("-" + Self.format(max(player.duration - shown, 0)))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.65))
        }
    }

    private var transport: some View {
        HStack {
            Button { player.skip(by: -15) } label: {
                Image(systemName: "gobackward.15").font(.title2)
            }
            Spacer()
            Button { player.previous() } label: {
                Image(systemName: "backward.fill").font(.system(size: 34))
            }
            Spacer()
            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 50))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 70, height: 70)
            }
            Spacer()
            Button { player.next() } label: {
                Image(systemName: "forward.fill").font(.system(size: 34))
            }
            Spacer()
            Button { player.skip(by: 15) } label: {
                Image(systemName: "goforward.15").font(.title2)
            }
        }
        .buttonStyle(.plain)
    }

    private var volume: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill").font(.caption)
            SystemVolumeSlider().frame(height: 34)
            Image(systemName: "speaker.wave.3.fill").font(.caption)
        }
        .foregroundStyle(.white.opacity(0.7))
    }

    private var bottomRow: some View {
        HStack {
            SleepTimerMenu()
            Spacer()
            Button { player.toggleShuffle() } label: {
                Image(systemName: "shuffle")
                    .font(.title3)
                    .foregroundStyle(player.isShuffled ? Color.accentColor : .white.opacity(0.75))
            }
            Spacer()
            AirPlayButton().frame(width: 36, height: 36)
            Spacer()
            Button { player.cycleRepeat() } label: {
                Image(systemName: player.repeatMode.systemImage)
                    .font(.title3)
                    .foregroundStyle(player.repeatMode == .off ? .white.opacity(0.75) : Color.accentColor)
            }
            Spacer()
            Button { showQueue = true } label: {
                Image(systemName: "list.bullet").font(.title3)
            }
        }
        .buttonStyle(.plain)
    }

    private func speedText(_ speed: Float) -> String {
        speed == 1 ? "1×" : String(format: "%g×", speed)
    }

    static func format(_ time: TimeInterval) -> String {
        guard time.isFinite else { return "0:00" }
        let total = Int(time.rounded(.down))
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

// MARK: - 잠자기 타이머

struct SleepTimerMenu: View {
    @EnvironmentObject private var player: AudioPlayer

    var body: some View {
        Menu {
            if player.isSleepTimerActive {
                Button(role: .destructive) {
                    player.cancelSleepTimer()
                } label: {
                    Label("타이머 끄기", systemImage: "xmark")
                }
            }
            Section("잠자기 타이머 — 끝나면 서서히 소리가 줄어들며 멈춤") {
                ForEach(SleepTimerOption.all) { option in
                    Button(option.title) { player.setSleepTimer(option) }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: player.isSleepTimerActive ? "moon.zzz.fill" : "moon.zzz")
                    .font(.title3)
                if let end = player.sleepTimerEnd {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(NowPlayingView.format(max(end.timeIntervalSince(context.date), 0)))
                            .font(.caption.monospacedDigit())
                    }
                } else if player.sleepAtEndOfTrack {
                    Text("곡 끝").font(.caption)
                }
            }
            .foregroundStyle(player.isSleepTimerActive ? Color.accentColor : .white.opacity(0.75))
        }
        .accessibilityLabel("잠자기 타이머")
    }
}

// MARK: - 재생 대기열

struct QueueView: View {
    @EnvironmentObject private var player: AudioPlayer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let item = player.current {
                    Section("지금 재생 중") {
                        HStack(spacing: 12) {
                            ArtworkView(image: player.info.artwork, size: 48, cornerRadius: 6)
                            VStack(alignment: .leading) {
                                Text(player.title).lineLimit(2)
                                Text(item.folder ?? "AudioOnly").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section {
                    if player.upNext.isEmpty {
                        Text(player.repeatMode == .off ? "다음 곡이 없습니다." : "반복 재생: 처음부터 다시 재생합니다.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(player.upNext.enumerated()), id: \.offset) { _, item in
                        Button {
                            player.jump(to: item)
                        } label: {
                            HStack(spacing: 12) {
                                FileArtworkView(url: item.url, size: 40)
                                VStack(alignment: .leading) {
                                    Text(item.name).lineLimit(2).foregroundStyle(.primary)
                                    if let folder = item.folder {
                                        Text(folder).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .onMove { player.moveUpNext(from: $0, to: $1) }
                    .onDelete { player.removeUpNext(at: $0) }
                } header: {
                    HStack {
                        Text("다음 재생")
                        Spacer()
                        Button {
                            player.toggleShuffle()
                        } label: {
                            Image(systemName: "shuffle")
                                .foregroundStyle(player.isShuffled ? Color.accentColor : .secondary)
                        }
                        Button {
                            player.cycleRepeat()
                        } label: {
                            Image(systemName: player.repeatMode.systemImage)
                                .foregroundStyle(player.repeatMode == .off ? .secondary : Color.accentColor)
                        }
                    }
                    .font(.body)
                    .buttonStyle(.borderless)
                }
            }
            .navigationTitle("재생 대기열")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - 시스템 볼륨 / AirPlay

/// 기기 볼륨과 연동되는 슬라이더
struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.showsRouteButton = false
        view.tintColor = .white
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

/// AirPlay / 블루투스 출력 선택 버튼
struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = UIColor.white.withAlphaComponent(0.75)
        view.activeTintColor = .systemOrange
        view.prioritizesVideoDevices = false
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
