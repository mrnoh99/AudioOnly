import AVFoundation
import UIKit

enum OutputFormat: String, CaseIterable, Identifiable {
    case m4a, wav

    var id: String { rawValue }
    var fileExtension: String { rawValue }

    var displayName: String {
        switch self {
        case .m4a: return "M4A (AAC)"
        case .wav: return "WAV (무손실 PCM)"
        }
    }
}

enum ConversionError: LocalizedError {
    case noAudioTrack
    case exportUnavailable
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noAudioTrack: return "오디오 트랙이 없는 파일입니다."
        case .exportUnavailable: return "이 파일은 변환할 수 없습니다."
        case .failed(let message): return message
        }
    }
}

/// AVFoundation으로 영상/오디오에서 오디오만 뽑아 m4a 또는 wav로 저장한다.
enum AudioConverter {
    /// - Parameter passthrough: true면 재인코딩 없이 오디오를 그대로 옮긴다(이미 AAC인 m4a 입력용).
    static func exportM4A(
        from input: URL,
        to output: URL,
        passthrough: Bool = false,
        metadata: [AVMetadataItem] = [],
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let asset = AVURLAsset(url: input)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else { throw ConversionError.noAudioTrack }

        let preset = passthrough ? AVAssetExportPresetPassthrough : AVAssetExportPresetAppleM4A
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw ConversionError.exportUnavailable
        }
        try? FileManager.default.removeItem(at: output)
        if !metadata.isEmpty {
            session.metadata = metadata
        }

        let monitor = Task {
            for await state in session.states(updateInterval: 0.2) {
                if case .exporting(let exportProgress) = state {
                    progress(exportProgress.fractionCompleted)
                }
            }
        }
        defer { monitor.cancel() }

        do {
            // iOS 18 API: Task가 취소되면 내보내기도 취소된다.
            try await session.export(to: output, as: .m4a)
            progress(1)
        } catch {
            try? FileManager.default.removeItem(at: output)
            if Task.isCancelled { throw CancellationError() }
            throw error
        }
    }

    /// 16-bit 44.1kHz 스테레오 WAV로 변환
    static func exportWAV(
        from input: URL,
        to output: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let asset = AVURLAsset(url: input)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw ConversionError.noAudioTrack
        }
        let duration = try await asset.load(.duration).seconds

        let work = Task.detached(priority: .userInitiated) {
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ]
            let reader = try AVAssetReader(asset: asset)
            let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
            readerOutput.alwaysCopiesSampleData = false
            reader.add(readerOutput)

            try? FileManager.default.removeItem(at: output)
            let writer = try AVAssetWriter(outputURL: output, fileType: .wav)
            let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
            writerInput.expectsMediaDataInRealTime = false
            writer.add(writerInput)

            guard reader.startReading() else {
                throw reader.error ?? ConversionError.failed("파일을 읽을 수 없습니다.")
            }
            guard writer.startWriting() else {
                throw writer.error ?? ConversionError.failed("파일을 쓸 수 없습니다.")
            }
            writer.startSession(atSourceTime: .zero)

            while let buffer = readerOutput.copyNextSampleBuffer() {
                if Task.isCancelled {
                    reader.cancelReading()
                    writer.cancelWriting()
                    try? FileManager.default.removeItem(at: output)
                    throw CancellationError()
                }
                while !writerInput.isReadyForMoreMediaData {
                    usleep(2_000)
                }
                guard writerInput.append(buffer) else {
                    reader.cancelReading()
                    throw writer.error ?? ConversionError.failed("변환 중 오류가 발생했습니다.")
                }
                if duration > 0 {
                    let seconds = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
                    progress(min(max(seconds / duration, 0), 1))
                }
            }
            if reader.status == .failed {
                writer.cancelWriting()
                throw reader.error ?? ConversionError.failed("파일을 읽는 중 오류가 발생했습니다.")
            }
            writerInput.markAsFinished()
            await writer.finishWriting()
            guard writer.status == .completed else {
                throw writer.error ?? ConversionError.failed("WAV 저장에 실패했습니다.")
            }
            progress(1)
        }

        try await withTaskCancellationHandler {
            try await work.value
        } onCancel: {
            work.cancel()
        }
    }

    static func metadataItems(title: String, artist: String?, artwork: Data?) -> [AVMetadataItem] {
        func item(_ identifier: AVMetadataIdentifier, _ value: NSCopying & NSObjectProtocol) -> AVMetadataItem {
            let item = AVMutableMetadataItem()
            item.identifier = identifier
            item.value = value
            item.extendedLanguageTag = "und"
            return item
        }
        var items = [item(.commonIdentifierTitle, title as NSString)]
        if let artist, !artist.isEmpty {
            items.append(item(.commonIdentifierArtist, artist as NSString))
        }
        if let artwork, let jpeg = jpegData(from: artwork) {
            let art = AVMutableMetadataItem()
            art.identifier = .commonIdentifierArtwork
            art.value = jpeg as NSData
            art.dataType = kCMMetadataBaseDataType_JPEG as String
            items.append(art)
        }
        return items
    }

    private static func jpegData(from data: Data) -> Data? {
        if data.starts(with: [0xFF, 0xD8]) { return data }
        return UIImage(data: data)?.jpegData(compressionQuality: 0.9)
    }
}
