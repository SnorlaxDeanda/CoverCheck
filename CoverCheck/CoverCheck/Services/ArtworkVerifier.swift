import Foundation

struct VerificationOptions: Equatable {
    var compareWithOnlineReference: Bool = true
    var compareWithFolderArt: Bool = true
    var similarityThreshold: Double = 0.88
    var minimumArtworkDimension: Int = 500
}

enum ArtworkVerifier {
    static func verifyAlbum(
        tracks: [MusicTrack],
        folderArtwork: Data?,
        reference: ReferenceArtwork?,
        options: VerificationOptions,
        approvalStore: ApprovedArtworkStore = .shared,
        existingID: UUID? = nil
    ) -> AlbumVerification {
        let artist = tracks.first?.displayArtist ?? "Unknown Artist"
        let album = tracks.first?.displayAlbum ?? "Unknown Album"
        let albumKey = tracks.first?.albumKey ?? "\(artist.lowercased())|\(album.lowercased())"
        let embedded = tracks.first(where: { $0.artworkData != nil })?.artworkData
        let embeddedHash = tracks.compactMap(\.artworkHash).first

        var messages: [String] = []
        var status: ArtworkStatus = .ok

        let withArt = tracks.filter(\.hasEmbeddedArtwork)
        let withoutArt = tracks.filter { !$0.hasEmbeddedArtwork }

        if withArt.isEmpty {
            status = .missing
            messages.append("No embedded album art found on any track.")
        } else if !withoutArt.isEmpty {
            status = .inconsistent
            messages.append("\(withoutArt.count) of \(tracks.count) tracks are missing embedded artwork.")
        }

        let distinctHashes = Set(withArt.compactMap(\.artworkHash))
        if distinctHashes.count > 1 {
            status = worse(status, .inconsistent)
            messages.append("Tracks in this album embed different artwork images.")
        }

        if let size = withArt.compactMap(\.artworkPixelSize).first {
            let minSide = Int(min(size.width, size.height))
            if minSide > 0 && minSide < options.minimumArtworkDimension {
                messages.append("Embedded artwork is low resolution (\(minSide)px). Prefer at least \(options.minimumArtworkDimension)px.")
            }
        }

        if options.compareWithFolderArt {
            if let folderArtwork {
                let folderHash = ImageHasher.averageHash(from: folderArtwork)
                let currentEmbeddedHash = distinctHashes.first
                if let folderHash, let currentEmbeddedHash {
                    let score = ImageHasher.similarity(folderHash, currentEmbeddedHash)
                    if score < options.similarityThreshold {
                        status = worse(status, .folderMismatch)
                        messages.append(String(
                            format: "Embedded art does not match folder cover (%.0f%% similar).",
                            score * 100
                        ))
                    }
                } else if embedded == nil {
                    messages.append("Folder cover art is present, but tracks have no embedded art.")
                }
            } else {
                messages.append("No folder cover image (cover.jpg / folder.jpg) found.")
            }
        }

        var similarity: Double?
        if options.compareWithOnlineReference, let reference {
            if let currentEmbeddedHash = distinctHashes.first {
                let score = ImageHasher.similarity(currentEmbeddedHash, reference.hash)
                similarity = score
                if score < options.similarityThreshold {
                    status = worse(status, .likelyWrong)
                    messages.append(String(
                        format: "Embedded art differs from %@ reference cover (%.0f%% similar).",
                        reference.source,
                        score * 100
                    ))
                } else {
                    messages.append(String(
                        format: "Matches %@ reference cover (%.0f%% similar).",
                        reference.source,
                        score * 100
                    ))
                }
            } else if status == .missing {
                messages.append("Reference cover was found online; embed it to fix missing artwork.")
            }
        } else if options.compareWithOnlineReference, withArt.isEmpty == false {
            status = status == .ok ? .unverified : status
            messages.append("Could not find an online reference cover for this album.")
        }

        let userApproved = approvalStore.isApproved(albumKey: albumKey, artworkHash: embeddedHash)
        if userApproved {
            status = .approved
            messages.insert("You marked this cover as correct.", at: 0)
        } else if status == .ok && messages.isEmpty {
            messages.append("Embedded artwork looks consistent and correct.")
        }

        return AlbumVerification(
            id: existingID ?? UUID(),
            albumKey: albumKey,
            artist: artist,
            album: album,
            tracks: tracks.sorted(by: trackSort),
            status: status,
            messages: messages,
            embeddedArtworkData: embedded,
            folderArtworkData: folderArtwork,
            referenceArtworkData: reference?.data,
            referenceSource: reference?.source,
            similarityScore: similarity,
            isUserApproved: userApproved
        )
    }

    private static func worse(_ current: ArtworkStatus, _ candidate: ArtworkStatus) -> ArtworkStatus {
        let rank: [ArtworkStatus: Int] = [
            .ok: 0,
            .approved: 0,
            .unverified: 1,
            .missing: 2,
            .folderMismatch: 3,
            .inconsistent: 4,
            .likelyWrong: 5
        ]
        let currentRank = rank[current] ?? 0
        let candidateRank = rank[candidate] ?? 0
        return candidateRank > currentRank ? candidate : current
    }

    private static func trackSort(_ lhs: MusicTrack, _ rhs: MusicTrack) -> Bool {
        let leftDisc = lhs.discNumber ?? 1
        let rightDisc = rhs.discNumber ?? 1
        if leftDisc != rightDisc { return leftDisc < rightDisc }
        let leftTrack = lhs.trackNumber ?? Int.max
        let rightTrack = rhs.trackNumber ?? Int.max
        if leftTrack != rightTrack { return leftTrack < rightTrack }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
}
