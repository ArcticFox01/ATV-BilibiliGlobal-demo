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
}

class MyLiveViewController: StandardVideoCollectionViewController<LiveRoom> {
    override func setupCollectionView() {
        super.setupCollectionView()
        collectionVC.styleOverride = .sideBar
        collectionVC.pageSize = 10
        reloadInterval = 15 * 60
    }

    override func request(page: Int) async throws -> [LiveRoom] {
        try await WebRequest.requestLiveRoom(page: page)
    }

    override func goDetail(with record: LiveRoom) {
        let playerVC = LivePlayerViewController()
        playerVC.room = record
        present(playerVC, animated: true, completion: nil)
    }
}

class AreaLiveViewController: StandardVideoCollectionViewController<AreaLiveRoom> {
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
    }

    override func request(page: Int) async throws -> [AreaLiveRoom] {
        if areaID == 0 {
            return try await WebRequest.requestHotLiveRoom(page: page)
        } else if areaID == -1 {
            return try await WebRequest.requestRecommandLiveRoom(page: page)
        }
        return try await WebRequest.requestAreaLiveRoom(area: areaID, page: page)
    }

    override func goDetail(with record: AreaLiveRoom) {
        let playerVC = LivePlayerViewController()
        playerVC.room = record.toLiveRoom()
        present(playerVC, animated: true, completion: nil)
    }
}

struct LiveRoom: DisplayData, Codable {
    let title: String
    let room_id: Int
    let uname: String
    let area_v2_name: String
    let keyframe: String?
    let face: URL?
    let cover_from_user: URL?

    var ownerName: String { uname }
    var pic: URL? {
        if let keyframe {
            return URL(string: keyframe)
        }
        return nil
    }

    var avatar: URL? { face }

    var overlay: DisplayOverlay? {
        var leftItems = [DisplayOverlay.DisplayOverlayItem]()
        leftItems.append(DisplayOverlay.DisplayOverlayItem(icon: nil, text: area_v2_name))
        return DisplayOverlay(leftItems: leftItems)
    }
}

extension LiveRoom: PlayableData {
    var cid: Int { 0 }
    var aid: Int { 0 }
}

extension WebRequest.EndPoint {
    static let liveRoom = "https://api.live.bilibili.com/xlive/web-ucenter/v1/xfetter/GetWebList"
    static let hotLive = "https://api.live.bilibili.com/xlive/web-interface/v1/second/getListByArea"
    static let areaLive = "https://api.live.bilibili.com/xlive/web-interface/v1/second/getList"
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
        let rooms = try await requestPublicLiveRecommendations()
        let matches = rooms.filter { $0.area_v2_parent_id == area }
        return (matches.isEmpty ? rooms : matches).map { $0.asAreaLiveRoom() }
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

struct AreaLiveRoom: DisplayData, Codable, PlayableData {
    let title: String
    let roomid: Int
    let uname: String
    let system_cover: String
    let face: URL?
    let user_cover: URL?
    let parent_name: String
    let area_name: String
    let area_v2_name: String
    var ownerName: String { uname }
    var pic: URL? { URL(string: system_cover) }
    var avatar: URL? { face }
    var cid: Int { 0 }
    var aid: Int { 0 }

    var overlay: DisplayOverlay? {
        var leftItems = [DisplayOverlay.DisplayOverlayItem]()
        leftItems.append(DisplayOverlay.DisplayOverlayItem(icon: nil, text: area_v2_name))
        return DisplayOverlay(leftItems: leftItems)
    }

    func toLiveRoom() -> LiveRoom {
        return LiveRoom(title: title, room_id: roomid, uname: uname, area_v2_name: area_v2_name, keyframe: system_cover.isEmpty ? nil : system_cover, face: face, cover_from_user: user_cover)
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

    func asAreaLiveRoom() -> AreaLiveRoom {
        AreaLiveRoom(title: title,
                     roomid: roomid,
                     uname: uname,
                     system_cover: cover,
                     face: face,
                     user_cover: URL(string: cover),
                     parent_name: area_v2_parent_name ?? "",
                     area_name: area_v2_name,
                     area_v2_name: area_v2_name)
    }

    func asLiveRoom() -> LiveRoom {
        LiveRoom(title: title,
                 room_id: roomid,
                 uname: uname,
                 area_v2_name: area_v2_name,
                 keyframe: cover,
                 face: face,
                 cover_from_user: URL(string: cover))
    }
}
