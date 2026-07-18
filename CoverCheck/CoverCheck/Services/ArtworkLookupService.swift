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

    init(session: URLSession = .shared) {
        self.session = session
    }

    func lookup(artist: String, album: String) async -> ReferenceArtwork? {
        let key = "\(artist.lowercased())|\(album.lowercased())"
        if let cached = cache[key] {
            return cached
        }

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

            let (imageData, _) = try await session.data(from: artworkURL)
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

        var request = URLRequest(url: url)
        request.setValue("CoverCheck/1.0 (macOS album art verifier)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }

            let decoded = try JSONDecoder().decode(MusicBrainzReleaseSearch.self, from: data)
            guard let releaseID = decoded.releases.first?.id else { return nil }

            let coverURL = URL(string: "https://coverartarchive.org/release/\(releaseID)/front-500")!
            let (imageData, imageResponse) = try await session.data(from: coverURL)
            guard let imageHTTP = imageResponse as? HTTPURLResponse,
                  (200..<300).contains(imageHTTP.statusCode),
                  let hash = ImageHasher.averageHash(from: imageData) else {
                return nil
            }

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
