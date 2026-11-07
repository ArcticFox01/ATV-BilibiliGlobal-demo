//
//  LivePlayerViewModel.swift
//  BiliBiliGlobal
//
//  Created by yicheng on 2024/5/13.
//

import Alamofire
import Foundation
import SwiftyJSON

enum LiveError: String, LocalizedError {
    case noLiving
    case noPlaybackUrl
    case fetchApiFail

    var errorDescription: String? {
        switch self {
        case .noLiving:
            return "This live stream has ended."
        case .noPlaybackUrl:
            return "No playable stream is currently available."
        case .fetchApiFail:
            return "Unable to load this live stream."
        }
    }
}

class LivePlayerViewModel {
    init(room: LiveRoom) {
        self.room = room
        roomID = room.room_id
    }

    deinit {
        danMuProvider?.stop()
    }

    var onPluginReady: (([CommonPlayerPlugin]) -> Void)?
    var onError: ((String) -> Void)?
    var onQualityChangeError: ((String) -> Void)?

    private let playPlugin = URLPlayPlugin(referer: Keys.liveReferer, isLive: true)
    private let debugPlugin = DebugPlugin()

    func start() {
        // Native Info must be available before the first frame, even while
        // room details, artwork, or danmaku are still loading.
        let fallbackDescription = room.area_v2_name.isEmpty ? room.title : room.area_v2_name
        playPlugin.externalMetadata = [
            AVPlayerMetaUtils.createMetadataItem(for: .commonIdentifierTitle, value: room.title),
            AVPlayerMetaUtils.createMetadataItem(for: .iTunesMetadataTrackSubTitle, value: room.ownerName),
            AVPlayerMetaUtils.createMetadataItem(for: .commonIdentifierDescription, value: fallbackDescription),
        ].compactMap { $0 }
        playPlugin.onPlayFail = { [weak self] in
            self?.playerDidFailToPlay()
        }

        debugPlugin.additionDebugInfo = { [weak self] in
            self?.debugInfo() ?? ""
        }

        onPluginReady?([playPlugin, debugPlugin])
        let fallbackInfoPlugin = BVideoInfoPlugin(title: room.title,
                                                  subTitle: room.ownerName,
                                                  desp: fallbackDescription,
                                                  pic: room.pic,
                                                  viewPoints: nil)
        onPluginReady?([fallbackInfoPlugin])
        Task { [self] in
            do {
                try await refreshRoomsID()
                await MainActor.run {
                    let plugin = LiveStatisticsPlugin(roomID: roomID)
                    statisticsPlugin = plugin
                    onPluginReady?([plugin])
                }
                async let detailedInfo = fetchDespInfo()
                try await initPlayer()

                let danmu = await initDanmu()
                let linePlugin = LineCandidatesPlugin(candidates: playInfos, qualities: qualities) { [weak self] info in
                    guard let self else { return }
                    // Recovery should start with the route the user selected.
                    self.playInfos = [info] + self.allPlayInfos.filter { $0.url != info.url }
                    self.playPlugin.play(urlString: info.url)
                } onQualityChange: { [weak self] quality in
                    self?.changeQuality(quality)
                }
                self.linePlugin = linePlugin
                self.onPluginReady?(danmu + [linePlugin])

                if let info = await detailedInfo {
                    let subtitle = "\(room.ownerName)·\(info.parent_area_name) \(info.area_name)"
                    let desp = "\(info.description)\nTags:\(info.tags ?? "")"
                    let infoPlugin = BVideoInfoPlugin(title: info.title, subTitle: subtitle, desp: desp, pic: room.pic, viewPoints: nil)
                    self.onPluginReady?([infoPlugin])
                }
            } catch let err {
                await MainActor.run {
                    onError?(String(describing: err))
                }
            }
        }
    }

    func playerDidFailToPlay() {
        Task { @MainActor in
            if isChangingQuality {
                pendingRecovery = true
                return
            }
            guard !isRecovering else { return }
            isRecovering = true
            defer { isRecovering = false }
            do {
                playInfos = Array(playInfos.dropFirst())
                if playInfos.isEmpty {
                    retryCount += 1
                    if retryCount > 3 {
                        await MainActor.run {
                            onError?("No playable stream is currently available.")
                        }
                        return
                    }
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    try await initPlayer()
                    return
                } else {
                    try await playFirstInfo()
                }
            } catch let err {
                await MainActor.run {
                    onError?(err.localizedDescription)
                }
            }
        }
    }

    func debugInfo() -> String {
        return "\(playInfos.first?.formate ?? "") \(playInfos.first?.current_qn ?? 0) retry:\(retryCount)"
    }

    func fetchDespInfo() async -> WebRequest.LiveRoomInfo? {
        return try? await WebRequest.requestLiveBaseInfo(roomID: roomID)
    }

    // Private
    private var allPlayInfos = [LivePlayUrlInfo]()
    private var playInfos = [LivePlayUrlInfo]()
    private var qualities = [LiveQuality]()
    private var linePlugin: LineCandidatesPlugin?
    private var requestedQuality = 10000
    private var isChangingQuality = false
    private var pendingRecovery = false
    private var roomID: Int
    private let room: LiveRoom
    private var danMuProvider: LiveDanMuProvider?
    private var statisticsPlugin: LiveStatisticsPlugin?
    private var retryCount = 0
    private var isRecovering = false

    private func refreshRoomsID() async throws {
        let info = try await WebRequest.requestLiveRoomInit(roomID: roomID)
        if info.live_status != 1 {
            throw LiveError.noLiving
        }
        roomID = info.room_id
    }

    private func changeQuality(_ quality: Int) {
        Task { @MainActor in
            guard !isChangingQuality, !isRecovering else { return }
            isChangingQuality = true
            defer {
                isChangingQuality = false
                if pendingRecovery {
                    pendingRecovery = false
                    playerDidFailToPlay()
                }
            }
            do {
                try await initPlayer(quality: quality)
                retryCount = 0
            } catch {
                // Keep the current stream playing if a quality request fails.
                onQualityChangeError?(error.localizedDescription)
            }
        }
    }

    private func initPlayer(quality: Int? = nil) async throws {
        let quality = quality ?? requestedQuality
        let info = try await WebRequest.requestLiveStreams(roomID: roomID, quality: quality)
        var candidates = [LivePlayUrlInfo]()
        var acceptedQualities = Set<Int>()

        for stream in info.stream where stream.protocol_name == "http_hls" {
            for content in stream.format {
                guard content.formatName == "fmp4" || content.formatName == "ts" else { continue }
                let formate = content.formatName
                let codecs = content.codec
                for codec in codecs where codec.codecName == "avc" {
                    let qn = codec.currentQn
                    acceptedQualities.formUnion(codec.acceptQn ?? [])
                    acceptedQualities.insert(qn)
                    let baseUrl = codec.baseurl
                    for url_info in codec.urlInfo {
                        let host = url_info.host
                        let extra = url_info.extra
                        let url = "\(host)\(baseUrl)\(extra)"
                        let playInfo = LivePlayUrlInfo(formate: formate, url: url, current_qn: qn, codec_name: codec.codecName)
                        candidates.append(playInfo)
                    }
                }
            }
        }

        candidates.sort { lhs, rhs in
            let lhsFormatRank = lhs.formate == "fmp4" ? 0 : 1
            let rhsFormatRank = rhs.formate == "fmp4" ? 0 : 1
            if lhsFormatRank != rhsFormatRank {
                return lhsFormatRank < rhsFormatRank
            }
            return (lhs.current_qn ?? 0) > (rhs.current_qn ?? 0)
        }

        guard !candidates.isEmpty else { throw LiveError.noPlaybackUrl }
        let descriptions = info.gQnDesc ?? []
        let availableQualities = acceptedQualities.sorted(by: >).map { qn in
            descriptions.first { $0.qn == qn } ?? LiveQuality(qn: qn, desc: "Quality \(qn)", mediaBaseDesc: nil)
        }
        let playableCandidates = candidates
        await MainActor.run {
            requestedQuality = quality
            allPlayInfos = playableCandidates
            playInfos = playableCandidates
            qualities = availableQualities
            linePlugin?.update(candidates: playableCandidates, qualities: availableQualities)
            // Discard failures from the old player before installing its replacement.
            pendingRecovery = false
            playPlugin.play(urlString: playableCandidates[0].url)
        }
    }

    func playFirstInfo() async throws {
        if let info = playInfos.first {
            Logger.debug("play => \(playInfos)")
            await MainActor.run {
                playPlugin.play(urlString: info.url)
            }
        } else {
            throw LiveError.noPlaybackUrl
        }
    }

    @MainActor private func initDanmu() async -> [CommonPlayerPlugin] {
        danMuProvider = LiveDanMuProvider(roomID: roomID, removeDup: Settings.enableDanmuRemoveDup)
        danMuProvider?.onStatisticsChanged = { [weak statisticsPlugin] watchedCount, likeCount in
            DispatchQueue.main.async {
                statisticsPlugin?.update(watchedCount: watchedCount, likeCount: likeCount)
            }
        }
        let danmuPlugin = DanmuViewPlugin(provider: danMuProvider!)

        try? await danMuProvider?.start()
        var plugins: [CommonPlayerPlugin] = [danmuPlugin]
        if Settings.danmuMask, Settings.vnMask {
            let plugin = MaskViewPugin(maskView: danmuPlugin.danMuView, maskProvider: VMaskProvider())
            plugins.append(plugin)
        }

        return plugins
    }
}

struct LivePlayUrlInfo {
    let formate: String?
    let url: String
    let current_qn: Int?
    let codec_name: String?
}

extension WebRequest.EndPoint {
    static let liveRoomInfo = "https://api.live.bilibili.com/room/v1/Room/get_info"
    static let liveRoomStream = "https://api.live.bilibili.com/xlive/web-room/v2/index/getRoomPlayInfo"
    static let liveRoomInit = "https://api.live.bilibili.com/room/v1/Room/room_init"
}

extension WebRequest {
    struct LiveRoomInfo: Codable {
        let description: String
        let parent_area_name: String
        let title: String
        let tags: String?
        let area_name: String
        let hot_words: [String]?
    }

    static func requestLiveBaseInfo(roomID: Int) async throws -> LiveRoomInfo {
        return try await request(url: EndPoint.liveRoomInfo, parameters: ["room_id": roomID])
    }

    struct LiveRoomInit: Codable {
        var live_status: Int
        var room_id: Int
    }

    static func requestLiveRoomInit(roomID: Int) async throws -> LiveRoomInit {
        return try await request(url: EndPoint.liveRoomInit, parameters: ["id": roomID])
    }

    struct LivePlayInfo: Codable {
        let stream: [LiveStream]
        let gQnDesc: [LiveQuality]?

        enum CodingKeys: String, CodingKey {
            case stream
            case gQnDesc = "g_qn_desc"
        }
    }

    static func requestLiveStreams(roomID: Int, quality: Int = 10000) async throws -> LivePlayInfo {
        struct LiveRoomStreamInfo: Codable {
            let playurl_info: PlayUrlInfo

            struct PlayUrlInfo: Codable {
                let playurl: LivePlayInfo
            }
        }
        let info: LiveRoomStreamInfo = try await request(url: EndPoint.liveRoomStream,
                                                         parameters: ["room_id": roomID,
                                                                      "protocol": "0,1",
                                                                      "format": "0,1,2",
                                                                      "codec": "0,1",
                                                                      "qn": quality,
                                                                      "platform": "web",
                                                                      "ptype": "8",
                                                                      "dolby": "5",
                                                                      "panorama": 1])
        return info.playurl_info.playurl
    }
}

struct LiveStream: Codable {
    let format: [Format]
    let protocol_name: String

    struct Format: Codable {
        let formatName: String
        let codec: [Codec]
        let masterurl: String

        enum CodingKeys: String, CodingKey {
            case formatName = "format_name"
            case codec
            case masterurl = "master_url"
        }

        struct Codec: Codable {
            let urlInfo: [URLInfo]
            let codecName: String
            let currentQn: Int
            let acceptQn: [Int]?
            let baseurl: String

            enum CodingKeys: String, CodingKey {
                case urlInfo = "url_info"
                case codecName = "codec_name"
                case currentQn = "current_qn"
                case acceptQn = "accept_qn"
                case baseurl = "base_url"
            }

            struct URLInfo: Codable {
                let host: String
                let extra: String
            }
        }
    }
}

struct LiveQuality: Codable {
    let qn: Int
    let desc: String
    let mediaBaseDesc: MediaBaseDescription?

    // The API's quality ID is a tier, not a pixel height. Prefer its resolution
    // label when supplied, rather than guessing dimensions from the ID.
    var displayName: String {
        let detail = mediaBaseDesc?.detailDesc?.desc ?? ""
        return detail.isEmpty ? desc : detail
    }

    enum CodingKeys: String, CodingKey {
        case qn, desc
        case mediaBaseDesc = "media_base_desc"
    }

    struct MediaBaseDescription: Codable {
        let detailDesc: DetailDescription?

        enum CodingKeys: String, CodingKey {
            case detailDesc = "detail_desc"
        }

        struct DetailDescription: Codable {
            let desc: String
        }
    }
}
