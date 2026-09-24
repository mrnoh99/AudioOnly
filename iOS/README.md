# AudioOnly for iPad (iOS)

**iPad**(iPadOS 18 이상)를 주로 쓰도록 만든 YouTube 오디오 추출 앱입니다. iPhone에서도 동작합니다.

## iPad에서 쓰기

- **가로 전체 화면**: 왼쪽 사이드바 · 가운데 입력 화면 · 오른쪽 작업 패널을 한 번에 보여 줍니다.
  주소를 붙여넣으면서 진행 상황을 바로 볼 수 있습니다.
- **Split View / Slide Over / 좁은 창**: 자동으로 아래쪽 탭 막대 화면으로 바뀝니다.
  Safari나 YouTube 옆에 띄워 두고 쓰기 좋습니다.
- **드래그 앤 드롭**
  - Safari의 YouTube 링크를 ‘YouTube 주소’ 화면으로 끌어다 놓기
  - 파일 앱의 영상 파일을 ‘다운로드한 파일’ 화면으로 끌어다 놓기
  - 보관함의 오디오를 파일 앱, GarageBand, 메일 등으로 끌어서 내보내기
- **키보드 단축키**(Magic Keyboard 등): ⌘1 주소 · ⌘2 재생목록 · ⌘3 파일 · ⌘4 보관함 · ⌘5 설정, ⌘↩︎ 추출
- **여러 창**: Stage Manager에서 창을 여러 개 열 수 있습니다(작업 목록은 공유).
- 재생목록은 넓은 화면에서 썸네일과 함께 표시하고, 보관함은 검색할 수 있습니다.

| 탭 | 하는 일 |
| --- | --- |
| **주소** | YouTube 영상 주소(여러 줄 가능)를 붙여넣으면 오디오만 내려받습니다. |
| **재생목록** | 재생목록 주소로 전체 항목을 불러와 원하는 영상만 골라 추출합니다. |
| **파일** | 이미 받아 둔 영상(파일 앱 · 사진 보관함 · 다른 앱에서 ‘공유 → AudioOnly’)에서 오디오 트랙만 뽑아냅니다. |
| **보관함** | 진행 상황, 추출한 파일 재생 · 공유 · 삭제 |
| **설정** | 출력 형식(M4A / WAV), 앨범 아트, 재생목록 폴더/번호, 동시 작업 수 |

추출한 파일은 기본적으로 **파일 앱 → 나의 iPad → AudioOnly** 에 저장됩니다.
**설정 → 저장 위치 → 폴더 선택…** 에서 파일 앱의 다른 폴더(iCloud Drive, USB 드라이브 등)로 바꿀 수 있습니다.

## macOS 버전과 다른 점

iOS 앱은 yt-dlp · ffmpeg 같은 외부 프로그램을 실행할 수 없어서 다음으로 대신합니다.

- YouTube 스트림 찾기: [YouTubeKit](https://github.com/alexeichhorn/YouTubeKit) (Swift 패키지)
- 재생목록: YouTube 재생목록 페이지와 내부 browse API를 직접 해석 (100개 넘는 목록도 이어서 불러옴)
- 오디오 변환: AVFoundation
- 출력 형식: YouTube의 원본 AAC 오디오를 **재인코딩 없이 M4A**로 저장하거나 WAV로 변환합니다.
  iOS에는 MP3 인코더가 없어 MP3는 지원하지 않습니다.
- 다운로드는 앱이 화면에 떠 있을 때 진행됩니다. 작업 중에는 화면이 자동으로 꺼지지 않습니다.

## 빌드해서 iPad에 설치하기

App Store 정책상 YouTube 다운로드 앱은 배포할 수 없으므로 **직접 빌드해서 설치**합니다.

1. 저장소 루트의 **`AudioOnly.xcodeproj`** 를 Xcode(26 이상)로 엽니다. (YouTubeKit 패키지는 자동으로 받아집니다.)
2. 위쪽 스킴에서 **AudioOnly iPad** 를 고르고, 실행 대상에 연결한 iPad를 선택합니다.
   (**AudioOnly Mac** 스킴을 고른 채 iPad에 실행하면 *mismatched platform* 오류가 납니다.)
3. **AudioOnlyiOS 타깃 → Signing & Capabilities → Team** 에 본인 Apple ID 팀을 선택합니다.
   (번들 ID가 겹치면 `com.audioonly.ios` 를 다른 값으로 바꾸세요.)
4. ▶︎ 실행. 처음에는 iPad의 **설정 → 일반 → VPN 및 기기 관리**에서 개발자를 신뢰해야 합니다.

무료 Apple ID로 설치한 앱은 7일마다 다시 설치해야 합니다(유료 개발자 계정은 1년).

GitHub Actions가 서명되지 않은 `AudioOnly-unsigned.ipa` 도 만들어 둡니다.
AltStore나 Sideloadly 같은 사이드로딩 도구로 본인 Apple ID 서명을 해서 설치할 수 있습니다.

## 구조

```
AudioOnly.xcodeproj                     (루트) macOS · iOS 타깃이 함께 있는 Xcode 프로젝트
iOS/
└── AudioOnlyiOS
    ├── Info.plist                      파일 공유, 여러 창, ‘공유 → AudioOnly’ 설정
    ├── App/AudioOnlyiOSApp.swift       진입점, 탭 구성
    ├── Models/AppModel.swift           설정, 작업 큐, 보관함
    ├── Services/YouTubeAudioDownloader.swift  스트림 선택 + 분할 다운로드 + 태그
    ├── Services/PlaylistFetcher.swift  재생목록 해석
    ├── Services/AudioConverter.swift   AVFoundation M4A/WAV 변환
    ├── Services/FileStore.swift        저장 위치, 파일 이름, 가져오기
    ├── Services/AudioPlayer.swift      보관함 미리듣기
    └── Views/                          SwiftUI 화면
```

## 문제 해결

**“mismatched platform” / iPad를 실행 대상으로 고를 수 없음**

1. 스킴이 **AudioOnly iPad** 인지 확인하세요. **AudioOnly Mac** 은 macOS 앱이라 iPad에서 실행할 수 없습니다.
2. iPad의 iPadOS 버전을 지원하는 Xcode가 필요합니다. 예를 들어 **iPadOS 27 기기에는 Xcode 27 이상**이 필요합니다.
   Xcode → Settings → Components 에서 해당 iOS 플랫폼이 설치되어 있는지도 확인하세요.
3. 그래도 안 되면 **Product → Clean Build Folder**(⇧⌘K) 후 다시 실행하세요.
