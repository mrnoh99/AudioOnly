import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showFolderPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("저장 위치") {
                        Text(model.outputFolderDisplayName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Button {
                        showFolderPicker = true
                    } label: {
                        Label("폴더 선택…", systemImage: "folder.badge.gearshape")
                    }
                    if model.customOutputFolder != nil {
                        Button("기본 폴더로 되돌리기", role: .destructive) {
                            model.resetOutputFolder()
                        }
                    }
                    Button {
                        openInFilesApp(model.outputDirectory)
                    } label: {
                        Label("‘파일’ 앱에서 열기", systemImage: "arrow.up.forward.app")
                    }
                    if let error = model.outputFolderError {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                } header: {
                    Text("저장 위치")
                } footer: {
                    Text("‘파일’ 앱의 어느 폴더든 고를 수 있습니다: \(UIDevice.localStorageName), iCloud Drive, USB 드라이브, 다른 앱의 폴더 등. 보관함 탭에는 이 폴더의 오디오가 표시됩니다.")
                }

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
                    LabeledContent("현재 네트워크", value: model.network.state.title)
                    Text("YouTube 오디오는 **Wi-Fi에서만** 다운로드합니다. 셀룰러 데이터일 때 추가한 작업은 ‘Wi-Fi 대기’로 보관되고, Wi-Fi에 연결되면 자동으로 시작합니다. 앱을 껐다 켜도 대기 중인 작업은 남아 있습니다.")
                    Text("다운로드 중 Wi-Fi가 끊기면 받은 부분을 보관해 두었다가, 다시 연결되면 이어서 받습니다.")
                    Text("다운로드는 앱이 열려 있거나 음악을 재생 중일 때 진행됩니다.")
                } header: {
                    Text("다운로드 안내")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .navigationTitle("설정")
            .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder]) { result in
                switch result {
                case .success(let url):
                    model.setOutputFolder(url)
                case .failure(let error):
                    model.outputFolderError = error.localizedDescription
                }
            }
        }
    }

    /// `shareddocuments://` 로 '파일' 앱을 해당 폴더에서 연다.
    private func openInFilesApp(_ folder: URL) {
        var components = URLComponents()
        components.scheme = "shareddocuments"
        components.path = folder.path
        if let url = components.url {
            UIApplication.shared.open(url)
        }
    }
}
