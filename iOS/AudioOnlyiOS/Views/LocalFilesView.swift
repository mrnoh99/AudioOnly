import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// 사진 보관함에서 고른 영상을 앱 임시 폴더로 복사해 받는다.
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let folder = FileStore.importsDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent(received.file.lastPathComponent)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return PickedMovie(url: destination)
        }
    }
}

/// 이미 내려받은 영상 파일(파일 앱, 사진 보관함, 다른 앱에서 공유)에서 오디오 추출
struct LocalFilesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showImporter = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var isLoadingPhotos = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showImporter = true
                    } label: {
                        Label("파일 앱에서 선택", systemImage: "folder")
                    }
                    PhotosPicker(selection: $photoItems, matching: .videos, photoLibrary: .shared()) {
                        HStack {
                            Label("사진 보관함에서 선택", systemImage: "photo.on.rectangle")
                            if isLoadingPhotos {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isLoadingPhotos)
                } footer: {
                    Text("다른 앱에서 영상 파일을 ‘공유 → AudioOnly’로 보내도 여기에 추가됩니다.")
                }

                if let error = model.importError {
                    Section {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }

                Section("추출할 파일 \(model.pendingFiles.count)개") {
                    if model.pendingFiles.isEmpty {
                        Text("추가한 파일이 없습니다.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.pendingFiles, id: \.self) { file in
                        Label(file.lastPathComponent, systemImage: "film")
                            .lineLimit(2)
                    }
                    .onDelete { model.removePendingFiles(at: $0) }
                }
            }
            .navigationTitle("다운로드한 파일")
            .toolbar {
                if !model.pendingFiles.isEmpty {
                    EditButton()
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !model.pendingFiles.isEmpty {
                    Button {
                        model.enqueueLocalFiles(model.pendingFiles)
                        model.selectedTab = .library
                    } label: {
                        Label("\(model.pendingFiles.count)개 파일 오디오 추출 (\(model.format.displayName))", systemImage: "waveform")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding()
                    .background(.bar)
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.movie, .audiovisualContent, .audio],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    model.importFiles(urls)
                case .failure(let error):
                    model.importError = error.localizedDescription
                }
            }
            .onChange(of: photoItems) { items in
                guard !items.isEmpty else { return }
                loadPhotos(items)
            }
        }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) {
        isLoadingPhotos = true
        Task { @MainActor in
            var failed = 0
            for item in items {
                do {
                    if let movie = try await item.loadTransferable(type: PickedMovie.self) {
                        model.addImportedFile(movie.url)
                    } else {
                        failed += 1
                    }
                } catch {
                    failed += 1
                }
            }
            model.importError = failed > 0 ? "사진 보관함 영상 \(failed)개를 가져오지 못했습니다." : nil
            photoItems = []
            isLoadingPhotos = false
        }
    }
}
