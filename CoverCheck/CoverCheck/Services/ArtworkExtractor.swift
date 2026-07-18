import Foundation
import AVFoundation
import AppKit
import ImageIO

enum ArtworkExtractor {
    static let audioExtensions: Set<String> = [
        "mp3", "m4a", "aac", "alac", "flac", "aiff", "aif", "wav", "caf", "ogg", "wma"
    ]

    static let folderArtNames: [String] = [
        "cover.jpg", "cover.jpeg", "cover.png",
        "folder.jpg", "folder.jpeg", "folder.png",
        "album.jpg", "album.jpeg", "album.png",
        "front.jpg", "front.jpeg", "front.png",
        "Artwork.jpg", "Artwork.jpeg", "Artwork.png",
        "artwork.jpg", "artwork.jpeg", "artwork.png"
    ]

    static func isAudioFile(_ url: URL) -> Bool {
        audioExtensions.contains(url.pathExtension.lowercased())
    }

    static func loadTrack(from url: URL) async -> MusicTrack? {
        let asset = AVURLAsset(url: url)
        do {
            let metadata = try await asset.load(.commonMetadata)
            let formatMetadata = try await asset.load(.metadata)

            let title = await stringValue(for: .commonKeyTitle, in: metadata)
                ?? url.deletingPathExtension().lastPathComponent
            let artist = await stringValue(for: .commonKeyArtist, in: metadata) ?? ""
            let album = await stringValue(for: .commonKeyAlbumName, in: metadata) ?? ""
            let albumArtist = await stringValue(forKey: "albumArtist", in: formatMetadata)
                ?? await stringValue(forKey: "TPE2", in: formatMetadata)
                ?? artist
            let year = await stringValue(for: .commonKeyCreationDate, in: metadata)
            let trackNumber = await intValue(forKey: "trackNumber", in: formatMetadata)
                ?? await intValue(forKey: "TRCK", in: formatMetadata)
            let discNumber = await intValue(forKey: "discNumber", in: formatMetadata)
                ?? await intValue(forKey: "TPOS", in: formatMetadata)

            let artworkData = await artworkData(from: metadata) ?? await artworkData(from: formatMetadata)
            let hash = artworkData.flatMap { ImageHasher.averageHash(from: $0) }
            let pixelSize = artworkData.flatMap(imagePixelSize)

            return MusicTrack(
                id: UUID(),
                url: url,
                title: title,
                artist: artist,
                album: album,
                albumArtist: albumArtist.isEmpty ? artist : albumArtist,
                trackNumber: trackNumber,
                discNumber: discNumber,
                year: year,
                hasEmbeddedArtwork: artworkData != nil,
                artworkHash: hash,
                artworkData: artworkData,
                artworkPixelSize: pixelSize
            )
        } catch {
            return nil
        }
    }

    static func folderArtwork(in directory: URL) -> Data? {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        let byName = Dictionary(uniqueKeysWithValues: contents.map {
            ($0.lastPathComponent.lowercased(), $0)
        })

        for name in folderArtNames {
            if let match = byName[name.lowercased()], let data = try? Data(contentsOf: match) {
                return data
            }
        }

        // Fallback: any image file in the album folder.
        let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp"]
        if let imageURL = contents.first(where: { imageExtensions.contains($0.pathExtension.lowercased()) }),
           let data = try? Data(contentsOf: imageURL) {
            return data
        }
        return nil
    }

    // MARK: - Metadata helpers

    private static func stringValue(
        for key: AVMetadataKey,
        in items: [AVMetadataItem]
    ) async -> String? {
        for item in items where item.commonKey == key {
            if let value = try? await item.load(.stringValue), !value.isEmpty {
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private static func stringValue(forKey identifier: String, in items: [AVMetadataItem]) async -> String? {
        for item in items {
            let keyString = (item.key as? NSString) as String?
            let identifierString = item.identifier?.rawValue
            if keyString == identifier || identifierString?.localizedCaseInsensitiveContains(identifier) == true {
                if let value = try? await item.load(.stringValue), !value.isEmpty {
                    return value.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if let number = try? await item.load(.numberValue) {
                    return number.stringValue
                }
            }
        }
        return nil
    }

    private static func intValue(forKey identifier: String, in items: [AVMetadataItem]) async -> Int? {
        for item in items {
            let keyString = (item.key as? NSString) as String?
            let identifierString = item.identifier?.rawValue
            if keyString == identifier || identifierString?.localizedCaseInsensitiveContains(identifier) == true {
                if let number = try? await item.load(.numberValue) {
                    return number.intValue
                }
                if let string = try? await item.load(.stringValue),
                   let intValue = Int(string.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) {
                    return intValue
                }
            }
        }
        return nil
    }

    private static func artworkData(from items: [AVMetadataItem]) async -> Data? {
        for item in items {
            let isArtwork = item.commonKey == .commonKeyArtwork
                || item.identifier?.rawValue.localizedCaseInsensitiveContains("artwork") == true
                || (item.key as? NSString as String?)?.localizedCaseInsensitiveContains("covr") == true
                || (item.key as? NSString as String?)?.localizedCaseInsensitiveContains("APIC") == true

            guard isArtwork else { continue }

            if let data = try? await item.load(.dataValue), !data.isEmpty {
                return data
            }
            if let value = try? await item.load(.value) {
                if let data = value as? Data, !data.isEmpty {
                    return data
                }
                if let image = value as? NSImage, let data = image.tiffRepresentation {
                    return data
                }
            }
        }
        return nil
    }

    private static func imagePixelSize(from data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat else {
            return nil
        }
        return CGSize(width: width, height: height)
    }
}
