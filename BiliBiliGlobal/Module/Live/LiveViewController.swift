//
//  LiveViewController.swift
//  BiliBiliGlobal
//
//  Created by Etan Chen on 2021/3/28.
//

import Alamofire
import SwiftyJSON
import UIKit

class LiveViewController: CategoryViewController {
    override func viewDidLoad() {
        categories = [
            CategoryDisplayModel(title: "Following", contentVC: MyLiveViewController()),
            CategoryDisplayModel(title: "Recommended", contentVC: AreaLiveViewController(areaID: -1)),
            CategoryDisplayModel(title: "Popular", contentVC: AreaLiveViewController(areaID: 0)),
            CategoryDisplayModel(title: "Entertainment", contentVC: AreaLiveViewController(areaID: 1)),
            CategoryDisplayModel(title: "VTubers", contentVC: AreaLiveViewController(areaID: 9)),
            CategoryDisplayModel(title: "Online Games", contentVC: AreaLiveViewController(areaID: 2)),
            CategoryDisplayModel(title: "Mobile Games", contentVC: AreaLiveViewController(areaID: 3)),
            CategoryDisplayModel(title: "Single-player", contentVC: AreaLiveViewController(areaID: 6)),
            CategoryDisplayModel(title: "Lifestyle", contentVC: AreaLiveViewController(areaID: 10)),
            CategoryDisplayModel(title: "Radio", contentVC: AreaLiveViewController(areaID: 5)),
            CategoryDisplayModel(title: "Knowledge", contentVC: AreaLiveViewController(areaID: 11)),
            CategoryDisplayModel(title: "Esports", contentVC: AreaLiveViewController(areaID: 13)),
        ]
        super.viewDidLoad()
    }

    override func setViewController(vc: UIViewController) {
        let changedCategory = currentViewController !== vc
        super.setViewController(vc: vc)

        // Live availability changes frequently. Fetch a fresh list whenever the
        // user returns to a different Live category instead of reusing its cache.
        if changedCategory {
            (vc as? BLTabBarContentVCProtocol)?.reloadData()
        }
    }
}

class MyLiveViewController: StandardVideoCollectionViewController<LiveRoom> {
    private let thumbnailStatistics = LiveThumbnailStatisticsLoader()

    override func setupCollectionView() {
        super.setupCollectionView()
        collectionVC.styleOverride = .sideBar
        collectionVC.pageSize = 10
        reloadInterval = 15 * 60
        thumbnailStatistics.attach(to: collectionVC)
    }

    override func request(page: Int) async throws -> [LiveRoom] {
        let rooms = try await WebRequest.requestLiveRoom(page: page)
        thumbnailStatistics.load(rooms: rooms)
        return rooms
    }

    override func goDetail(with record: LiveRoom) {
        let playerVC = LivePlayerViewController()
        playerVC.room = record
        present(playerVC, animated: true, completion: nil)
    }
}

class AreaLiveViewController: StandardVideoCollectionViewController<AreaLiveRoom> {
    private let thumbnailStatistics = LiveThumbnailStatisticsLoader()
    let areaID: Int
    init(areaID: Int) {
        self.areaID = areaID
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func setupCollectionView() {
        super.setupCollectionView()
        collectionVC.styleOverride = .sideBar
        collectionVC.pageSize = 10
        reloadInterval = 15 * 60
        thumbnailStatistics.attach(to: collectionVC)
    }

    override func request(page: Int) async throws -> [AreaLiveRoom] {
        let rooms: [AreaLiveRoom]
        if areaID == 0 {
            rooms = try await WebRequest.requestHotLiveRoom(page: page)
        } else if areaID == -1 {
            rooms = try await WebRequest.requestRecommandLiveRoom(page: page)
        } else {
            rooms = try await WebRequest.requestAreaLiveRoom(area: areaID, page: page)
        }
        thumbnailStatistics.load(rooms: rooms)
        return rooms
    }

    override func goDetail(with record: AreaLiveRoom) {
        let playerVC = LivePlayerViewController()
        playerVC.room = record.toLiveRoom()
        present(playerVC, animated: true, completion: nil)
    }
}

private protocol LiveThumbnailData {
    var statisticsRoomID: Int { get }
    var area_v2_name: String { get }
    var watched_show: WebRequest.LiveStatistics.Watched? { get }
}

private final class LiveThumbnailStatisticsLoader {
    private weak var collectionVC: FeedCollectionViewController?
    private var statistics = [Int: WebRequest.LiveStatistics]()
    private var lastRequestedAt = [Int: Date]()
    private var pendingRoomIDs = [Int]()
    private var tasks = [Int: Task<Void, Never>]()

    deinit {
        tasks.values.forEach { $0.cancel() }
    }

    func attach(to collectionVC: FeedCollectionViewController) {
        self.collectionVC = collectionVC
        collectionVC.overlayProvider = { [weak self] data in
            guard let room = data as? any LiveThumbnailData else { return data.overlay }
            return liveThumbnailOverlay(area: room.area_v2_name,
                                        statistics: self?.statistics[room.statisticsRoomID],
                                        watched: room.watched_show)
        }
    }

    func load<T: LiveThumbnailData>(rooms: [T]) {
        for room in rooms {
            let roomID = room.statisticsRoomID
            guard roomID > 0, tasks[roomID] == nil, !pendingRoomIDs.contains(roomID),
                  lastRequestedAt[roomID].map({ Date().timeIntervalSince($0) >= 60 }) ?? true else { continue }
            pendingRoomIDs.append(roomID)
        }
        startPendingRequests()
    }

    private func startPendingRequests() {
        // Show the streams immediately and fill counts without replacing focused cards.
        while tasks.count < 4, !pendingRoomIDs.isEmpty {
            let roomID = pendingRoomIDs.removeFirst()
            lastRequestedAt[roomID] = Date()
            tasks[roomID] = Task { @MainActor [weak self] in
                let info = try? await WebRequest.requestLiveStatistics(roomID: roomID)
                guard !Task.isCancelled, let self else { return }
                if let info {
                    statistics[roomID] = info
                    collectionVC?.refreshVisibleOverlays()
                }
                tasks[roomID] = nil
                startPendingRequests()
            }
        }
    }
}

private func liveThumbnailOverlay(area: String, statistics: WebRequest.LiveStatistics?, watched: WebRequest.LiveStatistics.Watched?) -> DisplayOverlay {
    func countText(_ count: Int?) -> String {
        guard let count, count >= 0 else { return "—" }
        return count.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
    }
    return DisplayOverlay(leftItems: [
        .init(icon: "person.2", text: countText(statistics?.watched_show?.num ?? watched?.num)),
        .init(icon: "hand.thumbsup", text: countText(statistics?.like_info_v3?.total_likes)),
    ], badge: .init(color: UIColor.black.withAlphaComponent(0.65), text: area))
}

struct LiveRoom: DisplayData, Codable, LiveThumbnailData {
    let title: String
    let room_id: Int
    let uname: String
    let area_v2_name: String
    let keyframe: String?
    let face: URL?
    let cover_from_user: URL?
    var watched_show: WebRequest.LiveStatistics.Watched? = nil

    var statisticsRoomID: Int { room_id }

    var ownerName: String { uname }
    var pic: URL? {
        if let keyframe {
            return URL(string: keyframe)
        }
        return nil
    }

    var avatar: URL? { face }

    var overlay: DisplayOverlay? {
        liveThumbnailOverlay(area: area_v2_name, statistics: nil, watched: watched_show)
    }

    static func == (lhs: LiveRoom, rhs: LiveRoom) -> Bool { lhs.room_id == rhs.room_id }
    func hash(into hasher: inout Hasher) { hasher.combine(room_id) }
}

extension LiveRoom: PlayableData {
    var cid: Int { 0 }
    var aid: Int { 0 }
}

extension WebRequest.EndPoint {
    static let liveRoom = "https://api.live.bilibili.com/xlive/web-ucenter/v1/xfetter/GetWebList"
    static let hotLive = "https://api.live.bilibili.com/xlive/web-interface/v1/second/getListByArea"
    static let areaLive = "https://api.live.bilibili.com/xlive/web-interface/v1/second/getList"
    static let areaLiveFallback = "https://api.live.bilibili.com/room/v3/area/getRoomList"
    static let recommandLive = "https://api.live.bilibili.com/xlive/web-interface/v1/webMain/getMoreRecList"
}

extension WebRequest {
    static func requestLiveRoom(page: Int) async throws -> [LiveRoom] {
        struct Resp: Codable {
            let rooms: [LiveRoom]
        }
        do {
            let resp: Resp = try await request(url: EndPoint.liveRoom, parameters: ["page_size": 10, "page": page])
            return resp.rooms
        } catch RequestError.statusFail(code: -352, message: _) {
            return try await requestPublicLiveRecommendations().map { $0.asLiveRoom() }
        }
    }

    static func requestAreaLiveRoom(area: Int, page: Int) async throws -> [AreaLiveRoom] {
        struct Resp: Codable {
            let list: [AreaLiveRoom]
        }
        let parameters: [String: Any] = ["platform": "web", "parent_area_id": area, "area_id": 0, "page": page]
        do {
            let resp: Resp = try await request(url: EndPoint.areaLive, parameters: parameters)
            return resp.list
        } catch RequestError.statusFail(code: -352, message: _) {
            var fallbackParameters = parameters
            if [2, 3, 6].contains(area) {
                fallbackParameters["sort_type"] = "online"
            }
            let resp: Resp = try await request(url: EndPoint.areaLiveFallback, parameters: fallbackParameters)
            return resp.list
        }
    }

    static func requestHotLiveRoom(page: Int) async throws -> [AreaLiveRoom] {
        try await requestPublicLiveRecommendations().map { $0.asAreaLiveRoom() }
    }

    static func requestRecommandLiveRoom(page: Int) async throws -> [AreaLiveRoom] {
        try await requestPublicLiveRecommendations().map { $0.asAreaLiveRoom() }
    }

    private static func requestPublicLiveRecommendations() async throws -> [LiveRecommendationRoom] {
        struct Resp: Codable {
            let recommend_room_list: [LiveRecommendationRoom]
        }
        let resp: Resp = try await request(url: EndPoint.recommandLive,
                                           parameters: ["platform": "web", "web_location": 333_1007])
        return resp.recommend_room_list
    }
}

struct AreaLiveRoom: DisplayData, Codable, PlayableData, LiveThumbnailData {
    let title: String
    let roomid: Int
    let uname: String
    let system_cover: String
    let face: URL?
    let user_cover: URL?
    let parent_name: String
    let area_name: String
    let area_v2_name: String
    var watched_show: WebRequest.LiveStatistics.Watched? = nil
    var statisticsRoomID: Int { roomid }
    var ownerName: String { uname }
    var pic: URL? { URL(string: system_cover) }
    var avatar: URL? { face }
    var cid: Int { 0 }
    var aid: Int { 0 }

    var overlay: DisplayOverlay? {
        liveThumbnailOverlay(area: area_v2_name, statistics: nil, watched: watched_show)
    }

    static func == (lhs: AreaLiveRoom, rhs: AreaLiveRoom) -> Bool { lhs.roomid == rhs.roomid }
    func hash(into hasher: inout Hasher) { hasher.combine(roomid) }

    func toLiveRoom() -> LiveRoom {
        return LiveRoom(title: title, room_id: roomid, uname: uname, area_v2_name: area_v2_name, keyframe: system_cover.isEmpty ? nil : system_cover, face: face, cover_from_user: user_cover, watched_show: watched_show)
    }
}

private struct LiveRecommendationRoom: Codable {
    let title: String
    let roomid: Int
    let uname: String
    let cover: String
    let face: URL?
    let area_v2_parent_id: Int
    let area_v2_parent_name: String?
    let area_v2_name: String
    let watched_show: WebRequest.LiveStatistics.Watched?

    func asAreaLiveRoom() -> AreaLiveRoom {
        AreaLiveRoom(title: title,
                     roomid: roomid,
                     uname: uname,
                     system_cover: cover,
                     face: face,
                     user_cover: URL(string: cover),
                     parent_name: area_v2_parent_name ?? "",
                     area_name: area_v2_name,
                     area_v2_name: area_v2_name,
                     watched_show: watched_show)
    }

    func asLiveRoom() -> LiveRoom {
        LiveRoom(title: title,
                 room_id: roomid,
                 uname: uname,
                 area_v2_name: area_v2_name,
                 keyframe: cover,
                 face: face,
                 cover_from_user: URL(string: cover),
                 watched_show: watched_show)
    }
}
