import Foundation

struct ScanSummary: Sendable {
    let albums: [AlbumVerification]
    let trackCount: Int
    let duration: TimeInterval
}

final class MusicScanner: @unchecked Sendable {
    private let lookupService = ArtworkLookupService()
    private var isCancelled = false

    func cancel() {
        isCancelled = true
    }

    func reset() {
        isCancelled = false
    }

    func scan(
        root: URL,
        options: VerificationOptions,
        onPhase: @escaping (ScanPhase) async -> Void
    ) async throws -> ScanSummary {
        reset()
        let started = Date()
        let progress = ProgressThrottler<ScanPhase>(intervalMilliseconds: 120)

        await onPhase(.enumerating)
        let files = try enumerateAudioFiles(in: root)
        if isCancelled { await onPhase(.cancelled); throw CancellationError() }

        var tracks: [MusicTrack] = []
        tracks.reserveCapacity(files.count)

        for (index, file) in files.enumerated() {
            if isCancelled { await onPhase(.cancelled); throw CancellationError() }
            let phase = ScanPhase.readingTags(current: index + 1, total: files.count)
            let force = index == 0 || index + 1 == files.count || (index + 1) % 8 == 0
            await progress.submit(phase, force: force, emit: onPhase)
            if let track = await ArtworkExtractor.loadTrack(from: file) {
                tracks.append(track)
            }
        }
        await progress.flush(emit: onPhase)

        let grouped = Dictionary(grouping: tracks, by: \.albumKey)
        let keys = grouped.keys.sorted()
        var albums: [AlbumVerification] = []
        albums.reserveCapacity(keys.count)

        for (index, key) in keys.enumerated() {
            if isCancelled { await onPhase(.cancelled); throw CancellationError() }
            let phase = ScanPhase.verifying(current: index + 1, total: keys.count)
            let force = index == 0 || index + 1 == keys.count
            await progress.submit(phase, force: force, emit: onPhase)

            guard let albumTracks = grouped[key], let first = albumTracks.first else { continue }
            let folderArt = ArtworkExtractor.folderArtwork(in: first.url.deletingLastPathComponent())

            let reference: ReferenceArtwork?
            if options.compareWithOnlineReference {
                reference = await lookupService.lookup(
                    artist: first.displayArtist,
                    album: first.displayAlbum
                )
            } else {
                reference = nil
            }

            let verification = ArtworkVerifier.verifyAlbum(
                tracks: albumTracks,
                folderArtwork: folderArt,
                reference: reference,
                options: options,
                approvalStore: .shared
            )
            albums.append(verification)
        }
        await progress.flush(emit: onPhase)

        albums.sort {
            if $0.status.isIssue != $1.status.isIssue {
                return $0.status.isIssue && !$1.status.isIssue
            }
            return $0.artist.localizedCaseInsensitiveCompare($1.artist) == .orderedAscending
        }

        await onPhase(.finished)
        return ScanSummary(
            albums: albums,
            trackCount: tracks.count,
            duration: Date().timeIntervalSince(started)
        )
    }

    private func enumerateAudioFiles(in root: URL) throws -> [URL] {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw NSError(
                domain: "CoverCheck",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Selected path is not a folder."]
            )
        }

        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let url as URL in enumerator {
            if ArtworkExtractor.isAudioFile(url) {
                files.append(url)
            }
        }
        return files.sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
    }
}
