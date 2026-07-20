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
    private let lock = NSLock()
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
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[albumKey] else { return false }
        return entry.artworkHash == normalizedHash(artworkHash)
    }

    func approval(for albumKey: String) -> ApprovedArtworkEntry? {
        lock.lock()
        defer { lock.unlock() }
        return entries[albumKey]
    }

    func approve(albumKey: String, artworkHash: String?) {
        lock.lock()
        entries[albumKey] = ApprovedArtworkEntry(
            artworkHash: normalizedHash(artworkHash),
            approvedAt: Date()
        )
        let snapshot = entries
        lock.unlock()
        persist(snapshot)
    }

    func clear(albumKey: String) {
        lock.lock()
        entries.removeValue(forKey: albumKey)
        let snapshot = entries
        lock.unlock()
        persist(snapshot)
    }

    func clearAll() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
        persist([:])
    }

    private func normalizedHash(_ hash: String?) -> String {
        hash ?? ""
    }

    private func persist(_ snapshot: [String: ApprovedArtworkEntry]) {
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: defaultsKey)
        }
    }
}
