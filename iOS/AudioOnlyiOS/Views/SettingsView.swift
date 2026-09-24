import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("출력 형식", selection: $model.format) {
                        ForEach(OutputFormat.allCases) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    Toggle("썸네일을 앨범 아트로 넣기", isOn: $model.embedArtwork)
                        .disabled(model.format != .m4a)
                } header: {
                    Text("오디오")
                } footer: {
                    Text("YouTube 오디오는 재인코딩 없이 원본 AAC(M4A) 그대로 저장합니다. WAV는 용량이 약 10배 큽니다.")
                }

                Section("재생목록") {
                    Toggle("재생목록 이름으로 폴더 만들기", isOn: $model.playlistSubfolder)
                    Toggle("파일 이름 앞에 번호 붙이기", isOn: $model.playlistNumbering)
                }

                Section("작업") {
                    Stepper("동시 작업 수: \(model.maxConcurrent)", value: $model.maxConcurrent, in: 1...4)
                }

                Section {
                    Text("추출한 파일은 ‘파일’ 앱 → 나의 iPhone → AudioOnly 폴더에 저장됩니다.")
                    Text("다운로드는 앱이 화면에 떠 있을 때 진행됩니다. 백그라운드로 가면 잠시 후 멈출 수 있습니다.")
                } header: {
                    Text("안내")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .navigationTitle("설정")
        }
    }
}
