import AVFoundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

/// Convertit une seule fois un GIF / WebP / APNG animé en vidéo H.264.
/// Une vidéo est décodée par la puce média du Mac, alors qu'un GIF est décodé
/// image par image par le processeur : c'est ce qui rend le fond d'écran fluide et sobre.
enum AnimatedImageConverter {
    enum Failure: LocalizedError {
        case unreadable, writer(String)
        var errorDescription: String? {
            switch self {
            case .unreadable: "Image animée illisible."
            case .writer(let m): "Conversion impossible : \(m)"
            }
        }
    }

    static let cacheDirectory = SharedStore.directory.appendingPathComponent("Wallpapers", isDirectory: true)

    static func isAnimatedImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        return CGImageSourceGetCount(source) > 1
    }

    static func cachedVideo(for url: URL) async throws -> URL {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fingerprint = "\(url.path)|\(attributes[.size] ?? 0)|\((attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)"
        let hash = SHA256.hash(data: Data(fingerprint.utf8)).prefix(10).map { String(format: "%02x", $0) }.joined()
        let output = cacheDirectory.appendingPathComponent("\(hash).mp4")
        if FileManager.default.fileExists(atPath: output.path) { return output }

        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let temporary = cacheDirectory.appendingPathComponent("\(hash)-\(UUID().uuidString).tmp.mp4")
        try await Task.detached(priority: .utility) {
            try convert(url, to: temporary)
        }.value
        try? FileManager.default.removeItem(at: output)
        try FileManager.default.moveItem(at: temporary, to: output)
        return output
    }

    private static func convert(_ source: URL, to destination: URL) throws {
        guard let image = CGImageSourceCreateWithURL(source as CFURL, nil),
              case let count = CGImageSourceGetCount(image), count > 0,
              let first = CGImageSourceCreateImageAtIndex(image, 0, nil) else { throw Failure.unreadable }

        let scale = min(1, 3840 / Double(max(first.width, first.height)))
        let width = max(Int(Double(first.width) * scale) & ~1, 2)
        let height = max(Int(Double(first.height) * scale) & ~1, 2)

        let writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: max(3_000_000, width * height * 8),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw Failure.writer(writer.error?.localizedDescription ?? "?") }
        writer.startSession(atSourceTime: .zero)

        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        var time = CMTime.zero
        for index in 0..<count {
            try autoreleasepool {
                guard let frame = CGImageSourceCreateImageAtIndex(image, index, nil),
                      let pool = adaptor.pixelBufferPool else { return }
                var buffer: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
                guard let buffer else { throw Failure.writer("tampon vidéo") }

                CVPixelBufferLockBaseAddress(buffer, [])
                let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
                                    bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                    space: colorSpace,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
                ctx?.setFillColor(.black)
                ctx?.fill(rect)
                ctx?.interpolationQuality = .high
                ctx?.draw(frame, in: rect)
                CVPixelBufferUnlockBaseAddress(buffer, [])

                while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.002) }
                guard adaptor.append(buffer, withPresentationTime: time) else {
                    throw Failure.writer(writer.error?.localizedDescription ?? "écriture")
                }
                time = time + CMTime(seconds: frameDelay(image, index), preferredTimescale: 600)
            }
        }

        input.markAsFinished()
        writer.endSession(atSourceTime: time)
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed else { throw Failure.writer(writer.error?.localizedDescription ?? "?") }
    }

    /// Délai d'une image, en suivant les navigateurs (< 20 ms ⇒ 100 ms).
    private static func frameDelay(_ source: CGImageSource, _ index: Int) -> Double {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]
        let containers: [(CFString, CFString, CFString)] = [
            (kCGImagePropertyGIFDictionary, kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime),
            (kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime),
            (kCGImagePropertyWebPDictionary, kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime),
            (kCGImagePropertyHEICSDictionary, kCGImagePropertyHEICSUnclampedDelayTime, kCGImagePropertyHEICSDelayTime),
        ]
        for (dictionary, unclamped, clamped) in containers {
            guard let values = properties[dictionary] as? [CFString: Any] else { continue }
            let delay = (values[unclamped] as? Double) ?? (values[clamped] as? Double) ?? 0.1
            return delay < 0.02 ? 0.1 : delay
        }
        return 0.1
    }
}
