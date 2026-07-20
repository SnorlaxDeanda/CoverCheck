import Foundation

struct ReferenceArtwork: Sendable {
    let data: Data
    let hash: String
    let source: String
    let artworkURL: URL
}

actor ArtworkLookupService {
    private let session: URLSession
    private var cache: [String: ReferenceArtwork?] = [:]
    private var lastMusicBrainzRequest: ContinuousClock.Instant?
    /// MusicBrainz asks clients to stay at ~1 request/second.
    private let musicBrainzMinimumInterval: Duration = .milliseconds(1100)

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 12
            config.timeoutIntervalForResource = 20
            config.waitsForConnectivity = false
            config.httpAdditionalHeaders = [
                "User-Agent": "CoverCheck/1.0 (macOS; album art verifier; https://github.com/SnorlaxDeanda/CoverCheck)"
            ]
            self.session = URLSession(configuration: config)
        }
    }

    func lookup(artist: String, album: String) async -> ReferenceArtwork? {
        let key = "\(artist.lowercased())|\(album.lowercased())"
        if let cached = cache[key] {
            return cached
        }

        // Prefer iTunes — usually fast and reliable. CAA often redirects to archive.org and times out.
        let iTunesResult = await fetchFromITunes(artist: artist, album: album)
        let result: ReferenceArtwork?
        if let iTunesResult {
            result = iTunesResult
        } else {
            result = await fetchFromCoverArtArchive(artist: artist, album: album)
        }
        cache[key] = result
        return result
    }

    private func waitForMusicBrainzSlot() async {
        if let last = lastMusicBrainzRequest {
            let elapsed = last.duration(to: .now)
            if elapsed < musicBrainzMinimumInterval {
                try? await Task.sleep(for: musicBrainzMinimumInterval - elapsed)
            }
        }
        lastMusicBrainzRequest = .now
    }

    // MARK: - iTunes Search API

    private func fetchFromITunes(artist: String, album: String) async -> ReferenceArtwork? {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: "\(artist) \(album)"),
            URLQueryItem(name: "entity", value: "album"),
            URLQueryItem(name: "limit", value: "5")
        ]
        guard let url = components.url else { return nil }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }

            let decoded = try JSONDecoder().decode(ITunesSearchResponse.self, from: data)
            guard let match = decoded.results.first(where: {
                fuzzyContains($0.collectionName, album) && fuzzyContains($0.artistName, artist)
            }) ?? decoded.results.first,
                  let artworkURL = match.highResArtworkURL else {
                return nil
            }

            let imageData = try await fetchImageData(from: artworkURL, timeout: 10)
            guard let hash = ImageHasher.averageHash(from: imageData) else { return nil }
            return ReferenceArtwork(
                data: imageData,
                hash: hash,
                source: "Apple Music / iTunes",
                artworkURL: artworkURL
            )
        } catch {
            return nil
        }
    }

    // MARK: - MusicBrainz + Cover Art Archive

    private func fetchFromCoverArtArchive(artist: String, album: String) async -> ReferenceArtwork? {
        var components = URLComponents(string: "https://musicbrainz.org/ws/2/release/")!
        components.queryItems = [
            URLQueryItem(name: "query", value: #"release:"\#(album)" AND artist:"\#(artist)""#),
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "limit", value: "3")
        ]
        guard let url = components.url else { return nil }

        await waitForMusicBrainzSlot()

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue(
            "CoverCheck/1.0 (macOS; album art verifier; https://github.com/SnorlaxDeanda/CoverCheck)",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }

            let decoded = try JSONDecoder().decode(MusicBrainzReleaseSearch.self, from: data)
            guard let releaseID = decoded.releases.first?.id else { return nil }

            // Prefer JSON metadata with an explicit thumbnail URL (avoids long archive.org redirects).
            if let fromJSON = await fetchCoverArtFromReleaseJSON(releaseID: releaseID) {
                return fromJSON
            }

            // Fallback: smaller front image with a short timeout.
            let coverURL = URL(string: "https://coverartarchive.org/release/\(releaseID)/front-250")!
            let imageData = try await fetchImageData(from: coverURL, timeout: 8)
            guard let hash = ImageHasher.averageHash(from: imageData) else { return nil }

            return ReferenceArtwork(
                data: imageData,
                hash: hash,
                source: "Cover Art Archive",
                artworkURL: coverURL
            )
        } catch {
            return nil
        }
    }

    private func fetchCoverArtFromReleaseJSON(releaseID: String) async -> ReferenceArtwork? {
        guard let metaURL = URL(string: "https://coverartarchive.org/release/\(releaseID)") else {
            return nil
        }

        var request = URLRequest(url: metaURL)
        request.timeoutInterval = 8
        request.setValue(
            "CoverCheck/1.0 (macOS; album art verifier; https://github.com/SnorlaxDeanda/CoverCheck)",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }

            let decoded = try JSONDecoder().decode(CoverArtArchiveRelease.self, from: data)
            guard let imageURL = decoded.preferredImageURL else { return nil }

            let imageData = try await fetchImageData(from: imageURL, timeout: 8)
            guard let hash = ImageHasher.averageHash(from: imageData) else { return nil }

            return ReferenceArtwork(
                data: imageData,
                hash: hash,
                source: "Cover Art Archive",
                artworkURL: imageURL
            )
        } catch {
            return nil
        }
    }

    private func fetchImageData(from url: URL, timeout: TimeInterval) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func fuzzyContains(_ haystack: String?, _ needle: String) -> Bool {
        guard let haystack else { return false }
        let left = haystack.lowercased()
        let right = needle.lowercased()
        return left.contains(right) || right.contains(left)
    }
}

// MARK: - API models

private struct ITunesSearchResponse: Decodable {
    let results: [ITunesAlbum]
}

private struct ITunesAlbum: Decodable {
    let artistName: String?
    let collectionName: String?
    let artworkUrl100: String?

    var highResArtworkURL: URL? {
        guard let artworkUrl100 else { return nil }
        let upgraded = artworkUrl100.replacingOccurrences(of: "100x100bb", with: "600x600bb")
        return URL(string: upgraded)
    }
}

private struct MusicBrainzReleaseSearch: Decodable {
    let releases: [MusicBrainzRelease]
}

private struct MusicBrainzRelease: Decodable {
    let id: String
}

private struct CoverArtArchiveRelease: Decodable {
    let images: [CoverArtArchiveImage]

    var preferredImageURL: URL? {
        let front = images.first(where: { $0.front }) ?? images.first
        guard let front else { return nil }
        if let small = front.thumbnails?.small, let url = URL(string: small) {
            return url
        }
        if let large = front.thumbnails?.large, let url = URL(string: large) {
            return url
        }
        if let image = front.image {
            return URL(string: image)
        }
        return nil
    }
}

private struct CoverArtArchiveImage: Decodable {
    let front: Bool
    let image: String?
    let thumbnails: CoverArtArchiveThumbnails?
}

private struct CoverArtArchiveThumbnails: Decodable {
    let small: String?
    let large: String?
}
