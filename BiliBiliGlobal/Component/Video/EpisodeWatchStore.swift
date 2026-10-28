import Foundation

struct EpisodeWatchProgress: Codable, Equatable {
    var position: Double
    var duration: Double
    var isWatched: Bool
    var isManuallyUnwatched: Bool?

    var fraction: Float {
        duration > 0 ? Float(min(max(position / duration, 0), 1)) : 0
    }
}

/// Bilibili exposes only the latest episode in a season. Keep individual episode
/// completion locally, without assuming earlier episodes have been watched.
final class EpisodeWatchStore {
    static let shared = EpisodeWatchStore()
    static let didChangeNotification = Notification.Name("EpisodeWatchProgressDidChange")

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func progress(for episodeID: Int, accountID: Int?) -> EpisodeWatchProgress? {
        guard let accountID else { return nil }
        return records(accountID: accountID)[String(episodeID)]
    }

    func recordPlayback(episodeID: Int, accountID: Int?, position: Double, duration: Double, completed: Bool = false) {
        guard episodeID > 0, let accountID, position.isFinite, position > 0,
              duration.isFinite, duration > 0 else { return }
        let previous = progress(for: episodeID, accountID: accountID)
        let progress = EpisodeWatchProgress(position: min(position, duration), duration: duration,
                                            isWatched: completed || position / duration >= 0.9 || previous?.isWatched == true)
        save(progress, episodeID: episodeID, accountID: accountID)
    }

    func importProgress(episodeID: Int, accountID: Int?, position: Int, duration: Double) {
        let previous = progress(for: episodeID, accountID: accountID)
        // A delayed server snapshot must not undo an explicit reset. Otherwise,
        // merge forward so the latest episode can also finish on another device.
        guard previous?.isManuallyUnwatched != true, position == -1 || position > 0 else { return }
        recordPlayback(episodeID: episodeID, accountID: accountID,
                       position: max(previous?.position ?? 0, position == -1 ? duration : Double(position)), duration: duration,
                       completed: position == -1)
    }

    func setWatched(_ watched: Bool, episodeID: Int, accountID: Int?) {
        guard episodeID > 0, let accountID else { return }
        save(EpisodeWatchProgress(position: 0, duration: 0, isWatched: watched, isManuallyUnwatched: !watched),
             episodeID: episodeID, accountID: accountID)
    }

    private func records(accountID: Int) -> [String: EpisodeWatchProgress] {
        guard let data = defaults.data(forKey: key(accountID: accountID)),
              let records = try? JSONDecoder().decode([String: EpisodeWatchProgress].self, from: data) else { return [:] }
        return records
    }

    private func save(_ progress: EpisodeWatchProgress, episodeID: Int, accountID: Int) {
        var records = records(accountID: accountID)
        guard records[String(episodeID)] != progress else { return }
        records[String(episodeID)] = progress
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: key(accountID: accountID))
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    private func key(accountID: Int) -> String {
        "app.anime.episodeProgress.\(accountID)"
    }
}
