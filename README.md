# AudioOnly

YouTube에서 **오디오만** 추출하는 macOS 앱입니다 (SwiftUI, macOS 13 이상).

> 📱 **iPad(및 iPhone) 버전**은 [`iOS/`](iOS/README.md) 폴더에 있습니다.

| 탭 | 하는 일 |
| --- | --- |
| **YouTube 주소** | 개별 영상 주소(여러 줄 가능)를 붙여넣으면 오디오만 내려받습니다. |
| **재생목록** | 재생목록 주소로 항목을 불러와서 원하는 영상만 골라 오디오를 추출합니다. 재생목록 이름으로 하위 폴더를 만들고 번호를 붙일 수 있습니다. |
| **다운로드한 파일** | 이미 받아 둔 영상 파일(mp4, mkv, webm, mov …)이나 폴더를 끌어다 놓으면 ffmpeg로 오디오 트랙만 뽑아냅니다. |

- 출력 형식: MP3 / M4A(AAC) / Opus / FLAC / WAV, 비트레이트 128–320 kbps
- 메타데이터, 썸네일(앨범 아트) 넣기
- 동시 작업 수 조절, 진행률 표시, 취소/다시 시도, 로그 보기, Finder에서 보기
- 연령 제한 영상을 위한 브라우저 쿠키 사용(Safari/Chrome/Firefox/Edge/Brave)

## 필요한 도구

앱은 [yt-dlp](https://github.com/yt-dlp/yt-dlp)와 [ffmpeg](https://ffmpeg.org)를 사용합니다.

```bash
brew install yt-dlp ffmpeg
```

yt-dlp는 앱 안에서도 설치/업데이트할 수 있습니다 (설정 → 도구 → *yt-dlp 최신 버전으로 업데이트*).
이 경우 `~/Library/Application Support/AudioOnly/bin/yt-dlp` 에 저장됩니다.
YouTube 쪽 변경으로 다운로드가 실패하면 먼저 yt-dlp를 업데이트하세요.

앱은 `/opt/homebrew/bin`, `/usr/local/bin` 등에서 도구를 자동으로 찾으며, 설정에서 경로를 직접 지정할 수도 있습니다.

## 빌드 & 실행

### Xcode 프로젝트 (권장)

저장소 루트의 **`AudioOnly.xcodeproj`** 를 Xcode 16 이상으로 엽니다. 타깃(스킴)이 두 개 있습니다.

| 스킴 | 플랫폼 |
| --- | --- |
| **AudioOnly** | macOS 앱 (yt-dlp · ffmpeg 사용) |
| **AudioOnlyiOS** | iPad / iPhone 앱 ([자세히](iOS/README.md)) |

스킴을 고르고 ▶︎ 실행하면 됩니다. 소스 폴더(`Sources/AudioOnly`, `iOS/AudioOnlyiOS`)는 폴더 동기화 그룹이라 새 파일을 추가하면 자동으로 프로젝트에 포함됩니다.

### 명령줄 (macOS 앱)

Xcode(또는 Command Line Tools)가 설치된 Mac에서:

```bash
# 바로 실행
swift run

# .app 번들 만들기 → build/AudioOnly.app
./scripts/build-app.sh

# 유니버설(Apple Silicon + Intel) + DMG
UNIVERSAL=1 DMG=1 ./scripts/build-app.sh
```

GitHub Actions(`.github/workflows/build.yml`)가 푸시할 때마다 유니버설 `AudioOnly.zip` / `AudioOnly.dmg`와 iOS용 서명 안 된 `.ipa`를 빌드해서 아티팩트로 올립니다.
ad-hoc 서명만 된 앱이라 처음 열 때 Gatekeeper가 막으면 Finder에서 **우클릭 → 열기**를 누르거나 다음을 실행하세요.

```bash
xattr -dr com.apple.quarantine /Applications/AudioOnly.app
```

## 구조

```
Sources/AudioOnly
├── App/AudioOnlyApp.swift        앱 진입점, 창/설정 Scene
├── Models/AppSettings.swift      출력 형식·음질·폴더 등 설정(UserDefaults)
├── Models/JobQueue.swift         작업 큐(동시 실행 수 제한)와 실행기
├── Services/ProcessRunner.swift  외부 프로세스 실행 + 줄 단위 출력 스트리밍
├── Services/Commands.swift       yt-dlp / ffmpeg 인자 생성, 파일 이름 처리
├── Services/OutputParser.swift   진행률·제목·결과 파일·오류 해석
├── Services/PlaylistService.swift 재생목록 조회 (yt-dlp --flat-playlist -J)
├── Services/ToolManager.swift    yt-dlp / ffmpeg 찾기, yt-dlp 설치
└── Views/                        SwiftUI 화면
```

> 저작권이 있는 콘텐츠는 권리자의 허락을 받았거나 개인적인 용도로 허용되는 범위에서만 사용하세요.
