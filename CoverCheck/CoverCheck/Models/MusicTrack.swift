import Foundation
import CoreGraphics

struct MusicTrack: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let title: String
    let artist: String
    let album: String
    let albumArtist: String
    let trackNumber: Int?
    let discNumber: Int?
    let year: String?
    let hasEmbeddedArtwork: Bool
    let artworkHash: String?
    let artworkData: Data?
    let artworkPixelSize: CGSize?

    var displayArtist: String {
        let value = albumArtist.isEmpty ? artist : albumArtist
        return value.isEmpty ? "Unknown Artist" : value
    }

    var displayAlbum: String {
        album.isEmpty ? "Unknown Album" : album
    }

    var albumKey: String {
        "\(displayArtist.lowercased())|\(displayAlbum.lowercased())"
    }

    var fileName: String {
        url.lastPathComponent
    }
}

enum ArtworkStatus: String, CaseIterable, Identifiable {
    case ok = "OK"
    case approved = "Approved"
    case missing = "Missing"
    case inconsistent = "Inconsistent"
    case folderMismatch = "Folder Mismatch"
    case likelyWrong = "Likely Wrong"
    case unverified = "Unverified"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .ok: return "checkmark.seal.fill"
        case .approved: return "hand.thumbsup.fill"
        case .missing: return "photo.badge.exclamationmark"
        case .inconsistent: return "square.on.square.dashed"
        case .folderMismatch: return "folder.badge.questionmark"
        case .likelyWrong: return "exclamationmark.triangle.fill"
        case .unverified: return "questionmark.circle"
        }
    }

    var tint: ColorToken {
        switch self {
        case .ok, .approved: return .ok
        case .missing: return .warning
        case .inconsistent: return .warning
        case .folderMismatch: return .warning
        case .likelyWrong: return .error
        case .unverified: return .neutral
        }
    }

    var isIssue: Bool {
        switch self {
        case .ok, .approved, .unverified:
            return false
        case .missing, .inconsistent, .folderMismatch, .likelyWrong:
            return true
        }
    }
}

enum ColorToken {
    case ok, warning, error, neutral
}

struct AlbumVerification: Identifiable, Hashable {
    let id: UUID
    let albumKey: String
    let artist: String
    let album: String
    let tracks: [MusicTrack]
    let status: ArtworkStatus
    let messages: [String]
    let embeddedArtworkData: Data?
    let folderArtworkData: Data?
    let referenceArtworkData: Data?
    let referenceSource: String?
    let similarityScore: Double?
    let isUserApproved: Bool

    var trackCount: Int { tracks.count }

    var representativeArtworkHash: String? {
        tracks.compactMap(\.artworkHash).first
    }

    var artworkCoverage: Double {
        guard !tracks.isEmpty else { return 0 }
        let withArt = tracks.filter(\.hasEmbeddedArtwork).count
        return Double(withArt) / Double(tracks.count)
    }
}

enum ScanPhase: Equatable {
    case idle
    case enumerating
    case readingTags(current: Int, total: Int)
    case verifying(current: Int, total: Int)
    case applying(current: Int, total: Int)
    case finished
    case cancelled
    case failed(String)

    var label: String {
        switch self {
        case .idle: return "Ready"
        case .enumerating: return "Finding audio files…"
        case .readingTags(let current, let total):
            return "Reading tags \(current)/\(total)"
        case .verifying(let current, let total):
            return "Verifying artwork \(current)/\(total)"
        case .applying(let current, let total):
            return "Updating artwork \(current)/\(total)"
        case .finished: return "Scan complete"
        case .cancelled: return "Scan cancelled"
        case .failed(let message): return "Failed: \(message)"
        }
    }

    var progress: Double? {
        switch self {
        case .readingTags(let current, let total),
             .verifying(let current, let total),
             .applying(let current, let total):
            guard total > 0 else { return 0 }
            return Double(current) / Double(total)
        case .finished: return 1
        default: return nil
        }
    }
}
