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
/// 저장할 때 소리 크기를 `volumeGain`배로 키운다.
enum AudioConverter {
    /// 2.0 = 원래보다 100% 크게(+6dB). 16-bit 범위를 넘는 샘플은 최대값에서 잘린다.
    static let volumeGain: Float = 2.0

    /// AAC 256kbps 44.1kHz 스테레오 M4A로 변환
    static func exportM4A(
        from input: URL,
        to output: URL,
        metadata: [AVMetadataItem] = [],
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 256_000,
        ]
        try await transcode(
            from: input, to: output, fileType: .m4a, writerSettings: settings, metadata: metadata, progress: progress
        )
    }

    /// 16-bit 44.1kHz 스테레오 WAV로 변환
    static func exportWAV(
        from input: URL,
        to output: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        try await transcode(
            from: input, to: output, fileType: .wav, writerSettings: pcmSettings, metadata: [], progress: progress
        )
    }

    /// 읽을 때와 WAV로 쓸 때 쓰는 16-bit 44.1kHz 스테레오 PCM 형식
    private static var pcmSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
    }

    /// PCM으로 읽어 소리를 키운 뒤 `writerSettings` 형식으로 쓴다.
    private static func transcode(
        from input: URL,
        to output: URL,
        fileType: AVFileType,
        writerSettings: [String: Any],
        metadata: [AVMetadataItem],
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let asset = AVURLAsset(url: input)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw ConversionError.noAudioTrack
        }
        let duration = try await asset.load(.duration).seconds

        let work = Task.detached(priority: .userInitiated) {
            let reader = try AVAssetReader(asset: asset)
            let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: AudioConverter.pcmSettings)
            readerOutput.alwaysCopiesSampleData = false
            reader.add(readerOutput)

            try? FileManager.default.removeItem(at: output)
            let writer = try AVAssetWriter(outputURL: output, fileType: fileType)
            let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: writerSettings)
            writerInput.expectsMediaDataInRealTime = false
            guard writer.canAdd(writerInput) else {
                throw ConversionError.exportUnavailable
            }
            writer.add(writerInput)
            if !metadata.isEmpty {
                writer.metadata = metadata
            }

            func fail(_ error: Error) -> Error {
                reader.cancelReading()
                writer.cancelWriting()
                try? FileManager.default.removeItem(at: output)
                return error
            }

            guard reader.startReading() else {
                throw reader.error ?? ConversionError.failed("파일을 읽을 수 없습니다.")
            }
            guard writer.startWriting() else {
                throw fail(writer.error ?? ConversionError.failed("파일을 쓸 수 없습니다."))
            }
            writer.startSession(atSourceTime: .zero)

            while let buffer = readerOutput.copyNextSampleBuffer() {
                if Task.isCancelled {
                    throw fail(CancellationError())
                }
                let louder = try AudioConverter.amplified(buffer, gain: AudioConverter.volumeGain)
                while !writerInput.isReadyForMoreMediaData {
                    usleep(2_000)
                }
                guard writerInput.append(louder) else {
                    throw fail(writer.error ?? ConversionError.failed("변환 중 오류가 발생했습니다."))
                }
                if duration > 0 {
                    let seconds = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
                    progress(min(max(seconds / duration, 0), 1))
                }
            }
            if reader.status == .failed {
                throw fail(reader.error ?? ConversionError.failed("파일을 읽는 중 오류가 발생했습니다."))
            }
            writerInput.markAsFinished()
            await writer.finishWriting()
            guard writer.status == .completed else {
                try? FileManager.default.removeItem(at: output)
                throw writer.error ?? ConversionError.failed("저장에 실패했습니다.")
            }
            progress(1)
        }

        try await withTaskCancellationHandler {
            try await work.value
        } onCancel: {
            work.cancel()
        }
    }

    /// 16-bit PCM 샘플 버퍼의 소리를 `gain`배로 키운 새 버퍼를 만든다. 범위를 넘는 값은 최대값으로 자른다.
    private static func amplified(_ buffer: CMSampleBuffer, gain: Float) throws -> CMSampleBuffer {
        guard let source = CMSampleBufferGetDataBuffer(buffer),
              let format = CMSampleBufferGetFormatDescription(buffer)
        else { return buffer }
        let length = CMBlockBufferGetDataLength(source)
        guard length > 0 else { return buffer }

        var block: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: length,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: length,
            flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &block
        )
        guard status == kCMBlockBufferNoErr, let block else {
            throw ConversionError.failed("소리 크기를 바꾸지 못했습니다.")
        }
        var pointer: UnsafeMutablePointer<CChar>?
        status = CMBlockBufferGetDataPointer(
            block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: nil, dataPointerOut: &pointer
        )
        guard status == kCMBlockBufferNoErr, let pointer else {
            throw ConversionError.failed("소리 크기를 바꾸지 못했습니다.")
        }
        status = CMBlockBufferCopyDataBytes(source, atOffset: 0, dataLength: length, destination: pointer)
        guard status == kCMBlockBufferNoErr else {
            throw ConversionError.failed("소리 크기를 바꾸지 못했습니다.")
        }

        let samples = UnsafeMutableRawPointer(pointer).bindMemory(to: Int16.self, capacity: length / 2)
        for i in 0..<(length / 2) {
            let value = Float(samples[i]) * gain
            samples[i] = Int16(min(max(value, Float(Int16.min)), Float(Int16.max)))
        }

        var result: CMSampleBuffer?
        status = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            formatDescription: format,
            sampleCount: CMSampleBufferGetNumSamples(buffer),
            presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(buffer),
            packetDescriptions: nil,
            sampleBufferOut: &result
        )
        guard status == noErr, let result else {
            throw ConversionError.failed("소리 크기를 바꾸지 못했습니다.")
        }
        return result
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
