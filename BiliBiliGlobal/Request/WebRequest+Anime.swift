import Foundation

struct AnimeCard: Hashable, PlayableData {
    let seasonID: Int
    var episodeID: Int = 0
    var title: String
    var pic: URL?
    var ownerName: String = ""
    var badge: String = ""
    var progress: Float?
    var aid: Int { 0 }
    var cid: Int { 0 }

    func detailViewController() -> VideoDetailViewController {
        episodeID > 0 ? .create(epid: episodeID) : .create(seasonId: seasonID)
    }
}

// Current Android global Anime uses the overseas channel/index APIs on Bilibili.com.
// The legacy /pgc/page feed contains mainland-only seasons, even with an English locale.
struct AnimeAPIEntry: Decodable {
    struct NewEpisode: Decodable { let index_show: String?; let cover: URL? }
    struct Badge: Decodable { let text: String? }
    struct Report: Decodable { let season_id: String? }
    struct Timeline: Decodable {
        let date: String
        let day_of_week: Int
        let is_today: Int?
    }

    let season_id: Int?
    let ep_id: Int?
    let url: URL?
    let title: String?
    let cover: URL?
    let bg_img: URL?
    let badge: String?
    let badge_info: Badge?
    let sub_title: String?
    let index_show: String?
    let pub_index: String?
    let pub_time: String?
    let new_ep: NewEpisode?
    let report: Report?
    let timeline: Timeline?
    let sub_items: [AnimeAPIEntry]?

    var seasonID: Int? { season_id ?? report?.season_id.flatMap(Int.init) }
    var card: AnimeCard? {
        guard let seasonID, seasonID > 0, let title, !title.isEmpty else { return nil }
        // Upcoming schedule entries already have an ep_id, but link to the season
        // until that episode is published. Honor that route instead of requesting a missing episode.
        let episodeID = url?.lastPathComponent == "ss\(seasonID)" ? 0 : ep_id ?? 0
        var subtitle = new_ep?.index_show ?? index_show ?? sub_title ?? ""
        if let pub_index, !pub_index.isEmpty, pub_index != subtitle {
            subtitle = [pub_index, subtitle].filter { !$0.isEmpty }.joined(separator: "\n")
        }
        return AnimeCard(seasonID: seasonID, episodeID: episodeID, title: title, pic: new_ep?.cover ?? cover ?? bg_img,
                         ownerName: subtitle,
                         badge: pub_time ?? badge_info?.text ?? badge ?? "")
    }
}

struct AnimeHomeResponse: Decodable {
    struct Module: Decodable {
        struct Content: Decodable { let items: [AnimeAPIEntry]? }
        let type: String
        let module_data: Content?
        var items: [AnimeAPIEntry] { module_data?.items ?? [] }
    }

    let modules: [Module]
    var featured: [AnimeCard] = []
    enum CodingKeys: String, CodingKey { case modules }

    var banners: [AnimeAPIEntry] { modules.filter { $0.type == "OVERSEA_BANNER" }.flatMap(\.items) }
    var popular: [AnimeCard] {
        var seen = Set<Int>()
        return modules.filter { $0.type == "DOUBLE_FEED" }.flatMap(\.items).compactMap(\.card)
            .filter { seen.insert($0.seasonID).inserted }
    }

    var schedule: [AnimeScheduleDay] {
        modules.filter { $0.type == "MIX_TIMELINE" }.flatMap(\.items).flatMap { $0.sub_items ?? [] }.compactMap { item in
            guard let date = item.timeline else { return nil }
            return AnimeScheduleDay(date: date.date, day_of_week: date.day_of_week,
                                    isToday: date.is_today == 1, cards: item.sub_items?.compactMap(\.card) ?? [])
        }
    }
}

struct AnimeCatalogResponse: Decodable {
    let list: [AnimeAPIEntry]
    let has_next: Int
}

struct AnimeCatalogConditions: Decodable {
    struct Order: Decodable {
        let field: String
        let name: String
        let sort: String
    }

    struct Value: Decodable {
        let name: String
        let keyword: String
    }

    struct Filter: Decodable {
        let field: String
        let name: String
        let values: [Value]
    }

    let order: [Order]
    let filter: [Filter]

    var rows: [Filter] {
        let sorting = Filter(field: "order", name: "Sort", values: order.map { Value(name: $0.name, keyword: $0.field) })
        return ([sorting] + filter).filter { !$0.values.isEmpty }
    }

    var defaults: [String: String] {
        Dictionary(uniqueKeysWithValues: rows.compactMap { row in row.values.first.map { (row.field, $0.keyword) } })
    }
}

struct AnimeScheduleDay {
    let date: String
    let day_of_week: Int
    let isToday: Bool
    let cards: [AnimeCard]
    var weekday: String { ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][max(0, min(day_of_week - 1, 6))] }
}

private struct AnimeHistoryResponse: Decodable {
    struct Record: Decodable {
        struct Route: Decodable { let business: String; let epid: Int }
        let history: Route
        let title: String
        let cover: URL?
        let show_title: String?
        let progress: Int
        let duration: Int
        var canResume: Bool {
            history.business == "pgc" && history.epid > 0 && progress >= 0 && duration > 0 && progress < duration - 10
        }

        func card(seasonID: Int) -> AnimeCard {
            AnimeCard(seasonID: seasonID, episodeID: history.epid, title: title, pic: cover,
                      ownerName: show_title ?? "", progress: Float(progress) / Float(duration))
        }
    }

    struct Cursor: Decodable { let max: Int; let view_at: Int; let business: String }
    let list: [Record]
    let cursor: Cursor
}

extension WebRequest {
    private static func requestAnime<T: Decodable>(_ path: String, parameters: [String: Any] = [:]) async throws -> T {
        var params: [String: Any] = [
            "mobi_app": "android_i", "platform": "android", "device": "phone", "build": 9_161_100,
            "c_locale": "en_US", "s_locale": "en_US",
            "x-bili-locale-json": #"{"c_locale":{"language":"en"},"always_translate":true}"#,
        ]
        params.merge(parameters) { _, value in value }
        if let accessKey = ApiRequest.getToken()?.accessToken, !accessKey.isEmpty { params["access_key"] = accessKey }
        // These read APIs accept the shared cookies, including cookie-only QR accounts.
        // ApiRequest.sign forces the legacy iPhone profile and must not replace android_i.
        return try await request(url: "https://api.bilibili.com/" + path, parameters: params,
                                 headers: ["Referer": "https://www.bilibili.com/en/", "User-Agent": Keys.liveUserAgent])
    }

    static func requestAnimeHome() async throws -> AnimeHomeResponse {
        var home: AnimeHomeResponse = try await requestAnime("pgc/page/channel", parameters: ["page_name": "bangumi_tab"])
        // Overseas banners carry artwork and a season ID, but no display title.
        home.featured = try await withThrowingTaskGroup(of: (Int, AnimeCard?).self) { group in
            for (index, banner) in home.banners.enumerated() {
                group.addTask {
                    guard let id = banner.seasonID, id > 0 else { return (index, nil) }
                    do {
                        let info = try await requestBangumiInfo(seasonID: id)
                        return (index, AnimeCard(seasonID: id, title: info.title ?? info.season_title ?? "Anime",
                                                 pic: banner.bg_img ?? info.horizontalCover ?? info.cover, ownerName: banner.sub_title ?? ""))
                    } catch {
                        try Task.checkCancellation()
                        return (index, nil)
                    }
                }
            }
            var cards: [(Int, AnimeCard)] = []
            for try await(index, card) in group {
                if let card { cards.append((index, card)) }
            }
            var seen = Set<Int>()
            return cards.sorted { $0.0 < $1.0 }.map { $0.1 }.filter { seen.insert($0.seasonID).inserted }
        }
        return home
    }

    static func requestAnimeCatalog(page: Int = 1, order: Int = 3, freeOnly: Bool = false,
                                    filters: [String: String] = [:]) async throws -> AnimeCatalogResponse
    {
        var parameters: [String: Any] = [
            // The Android overseas category browser uses the aggregate Anime index.
            // season_type=1 excludes most Chinese animation from region/style filters.
            "index_type": 103, "type": 0, "page": page, "pagesize": 24, "order": order, "sort": 0,
            "style_id": -1, "area": -1, "season_status": freeOnly ? "1" : "-1", "dub": "-1",
        ]
        filters.forEach { parameters[$0.key] = $0.value }
        return try await requestAnime("x/overseas/pgc/season/index/result", parameters: parameters)
    }

    static func requestAnimeCatalogConditions() async throws -> AnimeCatalogConditions {
        try await requestAnime("x/overseas/pgc/season/index/condition", parameters: ["index_type": 103, "type": 0])
    }

    static func requestAnimeSchedule() async throws -> [AnimeScheduleDay] {
        let home: AnimeHomeResponse = try await requestAnime("pgc/page/channel", parameters: ["page_name": "bangumi_tab"])
        let days = home.schedule
        guard let today = days.firstIndex(where: \.isToday) else { return Array(days.prefix(7)) }
        let start = max(0, today - days[today].day_of_week % 7)
        return Array(days.dropFirst(start).prefix(7))
    }

    private struct AnimeSeasonIdentity {
        let season_id: Int
        let type: Int
    }

    @MainActor private static var animeSeasonIdentities: [Int: AnimeSeasonIdentity] = [:]

    @MainActor private static func animeSeason(forEpisode episodeID: Int) async throws -> AnimeSeasonIdentity {
        if let season = animeSeasonIdentities[episodeID] { return season }
        // history.oid can be a video ID. Resolve the season using the saved episode ID.
        let info = try await requestBangumiInfo(epid: episodeID)
        let season = AnimeSeasonIdentity(season_id: info.season_id, type: info.type)
        animeSeasonIdentities[episodeID] = season
        return season
    }

    static func requestAnimeContinueWatching() async throws -> [AnimeCard] {
        guard AccountManager.shared.isLoggedIn else { return [] }
        var result: [AnimeCard] = []
        var seen = Set<Int>()
        var cursor: AnimeHistoryResponse.Cursor?
        // A short cursor walk finds Anime even when recent history contains mostly UGC.
        for _ in 0..<3 {
            var parameters: [String: Any] = ["ps": 30]
            if let cursor {
                parameters["max"] = cursor.max
                parameters["view_at"] = cursor.view_at
                parameters["business"] = cursor.business
            }
            let response: AnimeHistoryResponse = try await requestAnime("x/web-interface/history/cursor", parameters: parameters)
            let candidates = response.list.filter(\.canResume)
            // PGC also includes live-action films, dramas and documentaries.
            let resolved = try await withThrowingTaskGroup(of: (Int, AnimeCard?, Bool).self) { group in
                for (index, record) in candidates.enumerated() {
                    group.addTask {
                        do {
                            try Task.checkCancellation()
                            let season = try await animeSeason(forEpisode: record.history.epid)
                            let card = [1, 4].contains(season.type) ? record.card(seasonID: season.season_id) : nil
                            return (index, card, true)
                        } catch {
                            try Task.checkCancellation()
                            return (index, nil, false)
                        }
                    }
                }
                var items: [(Int, AnimeCard?, Bool)] = []
                for try await item in group {
                    items.append(item)
                }
                return items.sorted { $0.0 < $1.0 }
            }
            if result.isEmpty && !candidates.isEmpty && !resolved.contains(where: { $0.2 }) {
                throw "Couldn't look up the anime in your watch history. Please try again."
            }
            result.append(contentsOf: resolved.compactMap { $0.1 }.filter { seen.insert($0.seasonID).inserted })
            if result.count >= 12 || response.list.isEmpty || response.cursor.max == 0 { break }
            cursor = response.cursor
        }
        return Array(result.prefix(24))
    }
}
