# AudioOnly for iPhone & iPad

**iPhone과 iPad**(iOS / iPadOS 18 이상)에서 쓰는 YouTube 오디오 추출 · 재생 앱입니다. 하나의 앱이 두 기기에 모두 설치됩니다.

- **iPhone**: 아래쪽 탭 막대(주소 · 재생목록 · 파일 · 보관함 · 설정) + 미니 플레이어
- **iPad**: 사이드바 + 작업 패널 (좁은 창에서는 iPhone처럼 탭 막대)

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
| **보관함** | 진행 상황, 추출한 오디오를 음악 앱처럼 재생 (노래 / 폴더 보기, 재생·셔플) |
| **설정** | 출력 형식(M4A / WAV), 앨범 아트, 재생목록 폴더/번호, 동시 작업 수 |

추출한 파일은 기본적으로 **파일 앱 → 나의 iPhone(또는 나의 iPad) → AudioOnly** 에 저장됩니다.
**설정 → 저장 위치 → 폴더 선택…** 에서 파일 앱의 다른 폴더(iCloud Drive, USB 드라이브 등)로 바꿀 수 있습니다.

## Wi-Fi 다운로드

- YouTube 오디오는 셀룰러 데이터 요금이 나가지 않도록 **Wi-Fi에서만** 다운로드합니다.
- Wi-Fi가 아닐 때 추가한 작업은 **‘Wi-Fi 대기’** 로 보관되고, 화면 위쪽 안내에 이유와 대기 중인 개수가 표시됩니다.
- **Wi-Fi에 연결되면 자동으로 다운로드를 시작**하고, 보관함에서 곡별 진행률(받은 MB / 전체 MB)과 **전체 진행 막대**(완료 수, 진행·대기·실패 수)를 보여 줍니다.
- 다운로드 중 Wi-Fi가 끊기면 받은 부분을 보관했다가, 다시 연결되면 **이어서** 받습니다.
- 앱을 껐다 켜도 받지 못한 작업은 남아 있습니다.
- ‘파일’ 탭(이미 받은 영상에서 오디오 추출)은 Wi-Fi 없이도 됩니다.

## iCloud Drive 저장 폴더

저장 폴더를 iCloud Drive로 정하면, iOS가 공간을 아끼려고 일부 파일을 **iCloud에만 남기고 기기에서는 내용을 비울** 수 있습니다(목록에는 보이지만 바로 재생은 안 됨).

- 보관함에서 이런 파일은 ☁︎ 표시와 함께 “iCloud에만 있음”으로 나옵니다.
- 곡을 누르면 **Wi-Fi에서 iCloud로부터 받아 온 뒤 자동으로 재생**합니다. 받는 동안 목록·미니 플레이어·지금 재생 중 화면에 진행률이 표시됩니다.
- Wi-Fi가 아니면 ‘Wi-Fi 대기’로 두었다가 연결되면 받습니다.
- 보관함 위쪽 **모두 받기** 버튼으로 iCloud에만 있는 파일을 한꺼번에 받을 수 있습니다.

## 음악 플레이어

보관함의 오디오를 **Apple 음악 앱처럼** 재생합니다.

- **미니 플레이어**: 어느 화면에서든 아래쪽에 떠 있고, 누르거나 위로 밀면 전체 화면 **지금 재생 중**이 열립니다.
- **지금 재생 중**: 큰 앨범 아트(일시정지하면 살짝 작아짐), 흐린 앨범 아트 배경, 탐색 막대, 이전/다음, 15초 앞뒤로, 기기 볼륨, AirPlay, 재생 속도(0.5×–2×)
- **재생 대기열**: 다음 재생 목록 보기, 끌어서 순서 바꾸기, 밀어서 빼기, 셔플, 반복(전체 / 한 곡)
- 곡을 길게 누르거나 오른쪽으로 밀면 **다음에 재생 / 나중에 재생**을 고를 수 있습니다.
- **정렬**: 보관함 오른쪽 위 ↑↓ 버튼. 노래는 추가한 날짜 · 제목 · 폴더 · 크기 · 형식, 폴더는 이름 · 최근 추가 · 곡 수로 정렬하고 오름/내림차순을 고릅니다(설정은 기억됨). 곡을 누르면 보이는 순서대로 재생합니다.
- **잠자기 타이머**(🌙): 5분–1시간 30분 또는 *현재 곡이 끝나면*. 시간이 되면 **약 10초 동안 소리가 서서히 줄어든 뒤 조용히 멈춥니다.** 줄어드는 중에 재생 버튼을 누르면 타이머가 취소되고 계속 들을 수 있습니다.
- **백그라운드 재생**: 다른 앱으로 가거나 화면을 꺼도 계속 재생되고, 잠금 화면·제어 센터·이어폰 버튼으로 조작할 수 있습니다.
- 전화가 오면 멈췄다가 통화가 끝나면 이어서 재생하고, 이어폰을 빼면 스피커로 새어 나오지 않도록 멈춥니다.

## macOS 버전과 다른 점

iOS 앱은 yt-dlp · ffmpeg 같은 외부 프로그램을 실행할 수 없어서 다음으로 대신합니다.

- YouTube 스트림 찾기: [YouTubeKit](https://github.com/alexeichhorn/YouTubeKit) (Swift 패키지)
- 재생목록: YouTube 재생목록 페이지와 내부 browse API를 직접 해석 (100개 넘는 목록도 이어서 불러옴)
- 오디오 변환: AVFoundation
- 출력 형식: YouTube의 원본 AAC 오디오를 **재인코딩 없이 M4A**로 저장하거나 WAV로 변환합니다.
  iOS에는 MP3 인코더가 없어 MP3는 지원하지 않습니다.
- 다운로드는 앱이 화면에 떠 있을 때 진행됩니다. 작업 중에는 화면이 자동으로 꺼지지 않습니다.

## 빌드해서 iPhone · iPad에 설치하기

App Store 정책상 YouTube 다운로드 앱은 배포할 수 없으므로 **직접 빌드해서 설치**합니다.

1. 저장소 루트의 **`AudioOnly.xcodeproj`** 를 Xcode(26 이상)로 엽니다. (YouTubeKit 패키지는 자동으로 받아집니다.)
2. 위쪽 스킴에서 **AudioOnly iOS** 를 고르고, 실행 대상에 연결한 iPhone 또는 iPad를 선택합니다.
   (**AudioOnly Mac** 스킴을 고른 채 iPad에 실행하면 *mismatched platform* 오류가 납니다.)
3. **AudioOnlyiOS 타깃 → Signing & Capabilities → Team** 에 본인 Apple ID 팀을 선택합니다.
   (번들 ID가 겹치면 `com.audioonly.ios` 를 다른 값으로 바꾸세요.)
4. ▶︎ 실행. 처음에는 기기의 **설정 → 일반 → VPN 및 기기 관리**에서 개발자를 신뢰해야 합니다.

무료 Apple ID로 설치한 앱은 7일마다 다시 설치해야 합니다(유료 개발자 계정은 1년).

`main`에 올라간 최신 빌드는 [GitHub Releases의 **latest**](https://github.com/mrnoh99/AudioOnly/releases/tag/latest)에서 받을 수 있습니다. 서명되지 않은 `AudioOnly-unsigned.ipa`가 들어 있습니다.
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

**“mismatched platform” / iPhone · iPad를 실행 대상으로 고를 수 없음**

1. 스킴이 **AudioOnly iOS** 인지 확인하세요. **AudioOnly Mac** 은 macOS 앱이라 iPhone · iPad에서 실행할 수 없습니다.
2. 기기의 iOS 버전을 지원하는 Xcode가 필요합니다. 예를 들어 **iOS / iPadOS 27 기기에는 Xcode 27 이상**이 필요합니다.
   Xcode → Settings → Components 에서 해당 iOS 플랫폼이 설치되어 있는지도 확인하세요.
3. 그래도 안 되면 **Product → Clean Build Folder**(⇧⌘K) 후 다시 실행하세요.
