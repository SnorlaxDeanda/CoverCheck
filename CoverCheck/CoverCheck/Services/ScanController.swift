import Foundation
import AppKit
import Combine

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

    private let scanner = MusicScanner()
    private var scanTask: Task<Void, Never>?

    var isScanning: Bool {
        switch phase {
        case .enumerating, .readingTags, .verifying:
            return true
        default:
            return false
        }
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
            case .ok: matchesFilter = album.status == .ok
            case .missing: matchesFilter = album.status == .missing
            case .likelyWrong: matchesFilter = album.status == .likelyWrong
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
        guard let rootURL, !isScanning else { return }

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

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openOnlineReference(for album: AlbumVerification) {
        // Best-effort search page if we only stored source name.
        let query = "\(album.artist) \(album.album) cover art"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "https://www.google.com/search?tbm=isch&q=\(query)") {
            NSWorkspace.shared.open(url)
        }
    }
}

enum StatusFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case issues = "Issues"
    case ok = "OK"
    case missing = "Missing"
    case likelyWrong = "Likely Wrong"

    var id: String { rawValue }
}
