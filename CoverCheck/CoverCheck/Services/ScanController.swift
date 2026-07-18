import Foundation
import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
final class ScanController: ObservableObject {
    @Published var rootURL: URL?
    @Published var phase: ScanPhase = .idle
    @Published var albums: [AlbumVerification] = []
    @Published var selectedAlbumID: AlbumVerification.ID?
    @Published var trackCount: Int = 0
    @Published var duration: TimeInterval = 0
    @Published var statusFilter: StatusFilter = .all
    @Published var searchText: String = ""
    @Published var options = VerificationOptions()
    @Published var bookmarkData: Data?
    @Published var actionMessage: String?
    @Published var isApplyingArtwork = false

    private let scanner = MusicScanner()
    private let approvalStore = ApprovedArtworkStore.shared
    private var scanTask: Task<Void, Never>?
    private var lookupService = ArtworkLookupService()

    var isScanning: Bool {
        switch phase {
        case .enumerating, .readingTags, .verifying:
            return true
        default:
            return false
        }
    }

    var isBusy: Bool {
        isScanning || isApplyingArtwork
    }

    var selectedAlbum: AlbumVerification? {
        guard let selectedAlbumID else { return albums.first }
        return albums.first(where: { $0.id == selectedAlbumID }) ?? albums.first
    }

    var filteredAlbums: [AlbumVerification] {
        albums.filter { album in
            let matchesFilter: Bool
            switch statusFilter {
            case .all: matchesFilter = true
            case .issues: matchesFilter = album.status.isIssue
            case .ok: matchesFilter = album.status == .ok || album.status == .approved
            case .missing: matchesFilter = album.status == .missing
            case .likelyWrong: matchesFilter = album.status == .likelyWrong
            case .approved: matchesFilter = album.status == .approved
            }

            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = query.isEmpty
                || album.album.localizedCaseInsensitiveContains(query)
                || album.artist.localizedCaseInsensitiveContains(query)

            return matchesFilter && matchesSearch
        }
    }

    var issueCount: Int {
        albums.filter(\.status.isIssue).count
    }

    func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Scan"
        panel.message = "Choose a folder of music files to verify album art."

        if panel.runModal() == .OK, let url = panel.url {
            setRoot(url)
        }
    }

    func setRoot(_ url: URL) {
        rootURL = url
        albums = []
        selectedAlbumID = nil
        trackCount = 0
        duration = 0
        phase = .idle
        actionMessage = nil

        do {
            bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            bookmarkData = nil
        }
    }

    func startScan() async {
        guard let rootURL, !isBusy else { return }

        scanTask?.cancel()
        scanner.cancel()

        let accessed = rootURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                rootURL.stopAccessingSecurityScopedResource()
            }
        }

        albums = []
        selectedAlbumID = nil
        trackCount = 0
        duration = 0
        actionMessage = nil

        let options = self.options
        scanTask = Task { [weak self] in
            guard let self else { return }
            do {
                let summary = try await scanner.scan(root: rootURL, options: options) { phase in
                    self.phase = phase
                }
                self.albums = summary.albums
                self.trackCount = summary.trackCount
                self.duration = summary.duration
                self.selectedAlbumID = summary.albums.first?.id
                self.phase = .finished
            } catch is CancellationError {
                self.phase = .cancelled
            } catch {
                self.phase = .failed(error.localizedDescription)
            }
        }

        await scanTask?.value
    }

    func cancelScan() {
        scanner.cancel()
        scanTask?.cancel()
        phase = .cancelled
    }

    // MARK: - Approve / reject correctness

    func markAsCorrect(_ album: AlbumVerification) {
        approvalStore.approve(
            albumKey: album.albumKey,
            artworkHash: album.representativeArtworkHash
        )
        replaceAlbum(
            ArtworkVerifier.verifyAlbum(
                tracks: album.tracks,
                folderArtwork: album.folderArtworkData,
                reference: referenceArtwork(from: album),
                options: options,
                approvalStore: approvalStore,
                existingID: album.id
            )
        )
        actionMessage = "Marked “\(album.album)” as correct."
    }

    func clearApproval(_ album: AlbumVerification) {
        approvalStore.clear(albumKey: album.albumKey)
        replaceAlbum(
            ArtworkVerifier.verifyAlbum(
                tracks: album.tracks,
                folderArtwork: album.folderArtworkData,
                reference: referenceArtwork(from: album),
                options: options,
                approvalStore: approvalStore,
                existingID: album.id
            )
        )
        actionMessage = "Cleared approval for “\(album.album)”."
    }

    // MARK: - Apply / update covers

    func applyReferenceCover(to album: AlbumVerification) async {
        guard let data = album.referenceArtworkData else {
            actionMessage = "No reference cover is available for this album."
            return
        }
        await applyArtworkData(data, to: album, sourceLabel: "reference cover")
    }

    func applyFolderCover(to album: AlbumVerification) async {
        guard let data = album.folderArtworkData else {
            actionMessage = "No folder cover image was found."
            return
        }
        await applyArtworkData(data, to: album, sourceLabel: "folder cover")
    }

    func chooseAndApplyCover(to album: AlbumVerification) async {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.jpeg, .png, .webP, .heic, .tiff, .bmp, .gif]
        panel.prompt = "Use Cover"
        panel.message = "Choose an image to embed as album art for “\(album.album)”."

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let data = try Data(contentsOf: url)
            await applyArtworkData(data, to: album, sourceLabel: url.lastPathComponent)
        } catch {
            actionMessage = "Could not read image: \(error.localizedDescription)"
        }
    }

    private func applyArtworkData(_ imageData: Data, to album: AlbumVerification, sourceLabel: String) async {
        guard !isBusy else { return }
        guard let rootURL else { return }

        isApplyingArtwork = true
        actionMessage = "Updating artwork from \(sourceLabel)…"

        let accessed = rootURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { rootURL.stopAccessingSecurityScopedResource() }
            isApplyingArtwork = false
        }

        do {
            let jpeg = try ArtworkWriter.jpegData(from: imageData)
            let result = await ArtworkWriter.apply(jpegData: jpeg, to: album.tracks, updateFolderCover: true) { current, total in
                if current == 1 || current == total || current % 4 == 0 {
                    self.phase = .applying(current: current, total: total)
                }
            }

            let refreshed = await reloadAlbum(album)
            replaceAlbum(refreshed)
            selectedAlbumID = refreshed.id
            phase = .finished

            var summary = result.messages
            summary.insert("Applied \(sourceLabel) to “\(album.album)”.", at: 0)
            actionMessage = summary.joined(separator: " ")
        } catch {
            phase = .finished
            actionMessage = "Could not update artwork: \(error.localizedDescription)"
        }
    }

    private func reloadAlbum(_ album: AlbumVerification) async -> AlbumVerification {
        var tracks: [MusicTrack] = []
        for url in album.tracks.map(\.url) {
            if let track = await ArtworkExtractor.loadTrack(from: url) {
                tracks.append(track)
            }
        }

        let directory = (tracks.first ?? album.tracks.first)?.url.deletingLastPathComponent()
        let folderArt = directory.flatMap { ArtworkExtractor.folderArtwork(in: $0) }

        let reference: ReferenceArtwork?
        if options.compareWithOnlineReference {
            reference = await lookupService.lookup(artist: album.artist, album: album.album)
        } else if let data = album.referenceArtworkData,
                  let hash = ImageHasher.averageHash(from: data) {
            reference = ReferenceArtwork(
                data: data,
                hash: hash,
                source: album.referenceSource ?? "Reference",
                artworkURL: URL(fileURLWithPath: "/")
            )
        } else {
            reference = nil
        }

        return ArtworkVerifier.verifyAlbum(
            tracks: tracks.isEmpty ? album.tracks : tracks,
            folderArtwork: folderArt,
            reference: reference,
            options: options,
            approvalStore: approvalStore,
            existingID: album.id
        )
    }

    private func referenceArtwork(from album: AlbumVerification) -> ReferenceArtwork? {
        guard let data = album.referenceArtworkData,
              let hash = ImageHasher.averageHash(from: data) else {
            return nil
        }
        return ReferenceArtwork(
            data: data,
            hash: hash,
            source: album.referenceSource ?? "Reference",
            artworkURL: URL(fileURLWithPath: "/")
        )
    }

    private func replaceAlbum(_ album: AlbumVerification) {
        if let index = albums.firstIndex(where: { $0.id == album.id }) {
            albums[index] = album
        } else if let index = albums.firstIndex(where: { $0.albumKey == album.albumKey }) {
            albums[index] = album
        }
        selectedAlbumID = album.id
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openOnlineReference(for album: AlbumVerification) {
        let query = "\(album.artist) \(album.album) cover art"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "https://www.google.com/search?tbm=isch&q=\(query)") {
            NSWorkspace.shared.open(url)
        }
    }

    func dismissActionMessage() {
        actionMessage = nil
    }

    func clearAllApprovals() {
        approvalStore.clearAll()
        albums = albums.map { album in
            ArtworkVerifier.verifyAlbum(
                tracks: album.tracks,
                folderArtwork: album.folderArtworkData,
                reference: referenceArtwork(from: album),
                options: options,
                approvalStore: approvalStore,
                existingID: album.id
            )
        }
        actionMessage = "Cleared all saved cover approvals."
    }
}

enum StatusFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case issues = "Issues"
    case ok = "OK"
    case missing = "Missing"
    case likelyWrong = "Likely Wrong"
    case approved = "Approved"

    var id: String { rawValue }
}
