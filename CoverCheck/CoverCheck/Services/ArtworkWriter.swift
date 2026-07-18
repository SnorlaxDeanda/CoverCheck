import Foundation
import AppKit
import AVFoundation
import ImageIO

enum ArtworkWriteError: LocalizedError {
    case invalidImage
    case unsupportedFormat(String)
    case exportFailed(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Could not read the selected image."
        case .unsupportedFormat(let ext):
            return "Embedding artwork is not supported for .\(ext) files. Folder cover was updated when possible."
        case .exportFailed(let message):
            return "Failed to embed artwork: \(message)"
        case .writeFailed(let message):
            return message
        }
    }
}

struct ArtworkApplyResult: Sendable {
    var embeddedCount: Int = 0
    var skippedCount: Int = 0
    var folderUpdated: Bool = false
    var messages: [String] = []
}

enum ArtworkWriter {
    /// Normalize any image data to JPEG suitable for tags / cover.jpg.
    static func jpegData(from imageData: Data, maxDimension: CGFloat = 1400) throws -> Data {
        guard let image = NSImage(data: imageData) else {
            throw ArtworkWriteError.invalidImage
        }
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ArtworkWriteError.invalidImage
        }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let longest = max(width, height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let targetSize = CGSize(width: floor(width * scale), height: floor(height * scale))

        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(targetSize.width),
            pixelsHigh: Int(targetSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        guard let rep else { throw ArtworkWriteError.invalidImage }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSImage(cgImage: cgImage, size: targetSize).draw(
            in: CGRect(origin: .zero, size: targetSize),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        guard let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.88]) else {
            throw ArtworkWriteError.invalidImage
        }
        return jpeg
    }

    static func apply(
        jpegData: Data,
        to tracks: [MusicTrack],
        updateFolderCover: Bool = true,
        onProgress: (@MainActor (Int, Int) -> Void)? = nil
    ) async -> ArtworkApplyResult {
        var result = ArtworkApplyResult()

        if updateFolderCover, let directory = tracks.first?.url.deletingLastPathComponent() {
            do {
                try writeFolderCover(jpegData: jpegData, in: directory)
                result.folderUpdated = true
            } catch {
                result.messages.append("Folder cover: \(error.localizedDescription)")
            }
        }

        for (index, track) in tracks.enumerated() {
            await onProgress?(index + 1, tracks.count)
            do {
                try await embed(jpegData: jpegData, into: track.url)
                result.embeddedCount += 1
            } catch let error as ArtworkWriteError {
                result.skippedCount += 1
                if case .unsupportedFormat = error {
                    // Collapse repeated unsupported-format notes.
                    let note = error.localizedDescription
                    if !result.messages.contains(note) {
                        result.messages.append(note)
                    }
                } else {
                    result.messages.append("\(track.fileName): \(error.localizedDescription)")
                }
            } catch {
                result.skippedCount += 1
                result.messages.append("\(track.fileName): \(error.localizedDescription)")
            }
        }

        if result.embeddedCount > 0 {
            result.messages.insert(
                "Embedded artwork into \(result.embeddedCount) track\(result.embeddedCount == 1 ? "" : "s").",
                at: 0
            )
        }
        if result.folderUpdated {
            result.messages.insert("Updated folder cover.jpg.", at: 0)
        }

        return result
    }

    static func writeFolderCover(jpegData: Data, in directory: URL) throws {
        let coverURL = directory.appendingPathComponent("cover.jpg")
        try jpegData.write(to: coverURL, options: .atomic)
    }

    static func embed(jpegData: Data, into url: URL) async throws {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "mp3":
            try ID3ArtworkWriter.writeArtwork(to: url, jpegData: jpegData)
        case "m4a", "mp4", "aac", "alac":
            try await MPEG4ArtworkWriter.writeArtwork(to: url, jpegData: jpegData)
        default:
            throw ArtworkWriteError.unsupportedFormat(ext.isEmpty ? "unknown" : ext)
        }
    }
}

// MARK: - MP3 / ID3v2

enum ID3ArtworkWriter {
    static func writeArtwork(to url: URL, jpegData: Data) throws {
        let original = try Data(contentsOf: url)
        let (tagSize, preservedFrames) = parseID3v2(original)
        let audioData = original.subdata(in: tagSize..<original.count)

        let apic = makeAPICFrame(jpegData: jpegData)
        var frames = preservedFrames.filter { !$0.starts(with: Data("APIC".utf8)) }
        frames.append(apic)

        let tag = makeID3v2Tag(frames: frames)
        var output = Data()
        output.append(tag)
        output.append(audioData)

        let temp = url.appendingPathExtension("covercheck-tmp")
        try output.write(to: temp, options: .atomic)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
    }

    private static func parseID3v2(_ data: Data) -> (tagSize: Int, frames: [Data]) {
        guard data.count >= 10,
              data[0] == 0x49, data[1] == 0x44, data[2] == 0x33 else {
            return (0, [])
        }

        let versionMajor = data[3]
        let size = synchsafeInt(data[6], data[7], data[8], data[9])
        let tagEnd = min(data.count, 10 + size)
        var offset = 10
        var frames: [Data] = []

        // Skip extended header if present (v2.3/v2.4 flag bit).
        let flags = data[5]
        if flags & 0x40 != 0, offset + 4 <= tagEnd {
            let extSize: Int
            if versionMajor >= 4 {
                extSize = synchsafeInt(data[offset], data[offset + 1], data[offset + 2], data[offset + 3])
            } else {
                extSize = Int(data[offset]) << 24
                    | Int(data[offset + 1]) << 16
                    | Int(data[offset + 2]) << 8
                    | Int(data[offset + 3])
            }
            offset += 4 + max(0, extSize)
        }

        while offset + 10 <= tagEnd {
            let idData = data.subdata(in: offset..<(offset + 4))
            if idData[0] == 0 { break }
            let id = String(bytes: idData, encoding: .isoLatin1) ?? ""
            guard id.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) else { break }

            let frameSize: Int
            if versionMajor >= 4 {
                frameSize = synchsafeInt(data[offset + 4], data[offset + 5], data[offset + 6], data[offset + 7])
            } else {
                frameSize = Int(data[offset + 4]) << 24
                    | Int(data[offset + 5]) << 16
                    | Int(data[offset + 6]) << 8
                    | Int(data[offset + 7])
            }

            let frameTotal = 10 + frameSize
            guard frameSize >= 0, offset + frameTotal <= tagEnd else { break }

            if id != "APIC" {
                frames.append(data.subdata(in: offset..<(offset + frameTotal)))
            }
            offset += frameTotal
        }

        return (tagEnd, frames)
    }

    private static func makeAPICFrame(jpegData: Data) -> Data {
        var body = Data()
        body.append(0x00) // ISO-8859-1
        body.append(contentsOf: Array("image/jpeg".utf8))
        body.append(0x00)
        body.append(0x03) // Front cover
        body.append(0x00) // Empty description
        body.append(jpegData)

        var frame = Data()
        frame.append(contentsOf: Array("APIC".utf8))
        let size = body.count
        frame.append(contentsOf: [
            UInt8((size >> 24) & 0xFF),
            UInt8((size >> 16) & 0xFF),
            UInt8((size >> 8) & 0xFF),
            UInt8(size & 0xFF)
        ])
        frame.append(contentsOf: [0x00, 0x00]) // flags
        frame.append(body)
        return frame
    }

    private static func makeID3v2Tag(frames: [Data]) -> Data {
        var body = Data()
        for frame in frames {
            body.append(frame)
        }

        var tag = Data()
        tag.append(contentsOf: Array("ID3".utf8))
        tag.append(contentsOf: [0x03, 0x00]) // v2.3.0
        tag.append(0x00) // flags
        tag.append(contentsOf: encodeSynchsafe(body.count))
        tag.append(body)
        return tag
    }

    private static func synchsafeInt(_ b0: UInt8, _ b1: UInt8, _ b2: UInt8, _ b3: UInt8) -> Int {
        (Int(b0) & 0x7F) << 21
            | (Int(b1) & 0x7F) << 14
            | (Int(b2) & 0x7F) << 7
            | (Int(b3) & 0x7F)
    }

    private static func encodeSynchsafe(_ value: Int) -> [UInt8] {
        [
            UInt8((value >> 21) & 0x7F),
            UInt8((value >> 14) & 0x7F),
            UInt8((value >> 7) & 0x7F),
            UInt8(value & 0x7F)
        ]
    }
}

// MARK: - MPEG-4 / M4A

enum MPEG4ArtworkWriter {
    static func writeArtwork(to url: URL, jpegData: Data) async throws {
        let asset = AVURLAsset(url: url)
        let existing = (try? await asset.load(.metadata)) ?? []
        let withoutArtwork = existing.filter { item in
            item.commonKey != .commonKeyArtwork
                && item.identifier?.rawValue.localizedCaseInsensitiveContains("artwork") != true
        }

        let artwork = AVMutableMetadataItem()
        artwork.identifier = .commonIdentifierArtwork
        artwork.dataValue = jpegData

        let ext = url.pathExtension.lowercased()
        let outputType: AVFileType = (ext == "mp4") ? .mp4 : .m4a

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw ArtworkWriteError.exportFailed("Could not create export session.")
        }

        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext.isEmpty ? "m4a" : ext)

        session.outputURL = temp
        session.outputFileType = outputType
        session.metadata = withoutArtwork + [artwork]

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously {
                continuation.resume()
            }
        }

        switch session.status {
        case .completed:
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
            try? FileManager.default.removeItem(at: temp)
        case .failed:
            try? FileManager.default.removeItem(at: temp)
            let message = session.error?.localizedDescription ?? "Unknown export error"
            throw ArtworkWriteError.exportFailed(message)
        case .cancelled:
            try? FileManager.default.removeItem(at: temp)
            throw CancellationError()
        default:
            try? FileManager.default.removeItem(at: temp)
            throw ArtworkWriteError.exportFailed("Export did not complete.")
        }
    }
}
