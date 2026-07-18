import Foundation

/// Persists user confirmations that an album's current cover is correct.
struct ApprovedArtworkEntry: Codable, Equatable, Hashable {
    var artworkHash: String
    var approvedAt: Date
}

final class ApprovedArtworkStore {
    static let shared = ApprovedArtworkStore()

    private let defaultsKey = "covercheck.approvedArtwork"
    private let defaults: UserDefaults
    private var entries: [String: ApprovedArtworkEntry]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([String: ApprovedArtworkEntry].self, from: data) {
            entries = decoded
        } else {
            entries = [:]
        }
    }

    func isApproved(albumKey: String, artworkHash: String?) -> Bool {
        guard let entry = entries[albumKey] else { return false }
        return entry.artworkHash == normalizedHash(artworkHash)
    }

    func approval(for albumKey: String) -> ApprovedArtworkEntry? {
        entries[albumKey]
    }

    func approve(albumKey: String, artworkHash: String?) {
        entries[albumKey] = ApprovedArtworkEntry(
            artworkHash: normalizedHash(artworkHash),
            approvedAt: Date()
        )
        persist()
    }

    func clear(albumKey: String) {
        entries.removeValue(forKey: albumKey)
        persist()
    }

    func clearAll() {
        entries.removeAll()
        persist()
    }

    private func normalizedHash(_ hash: String?) -> String {
        hash ?? ""
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: defaultsKey)
        }
    }
}
