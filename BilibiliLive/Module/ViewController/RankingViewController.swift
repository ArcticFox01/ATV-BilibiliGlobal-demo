//
//  RankingViewController.swift
//  BilibiliLive
//
//  Created by yicheng on 2022/10/29.
//

import Foundation
import UIKit

struct RankCategoryInfo {
    let title: String
    let rid: Int
    var isSeason = false

    static let all = [RankCategoryInfo(title: "All", rid: 0),
                      RankCategoryInfo(title: "Animation", rid: 1005),
                      RankCategoryInfo(title: "Anime", rid: 1, isSeason: true),
                      RankCategoryInfo(title: "Chinese Animation", rid: 4, isSeason: true),
                      RankCategoryInfo(title: "Music", rid: 1003),
                      RankCategoryInfo(title: "Dance", rid: 1004),
                      RankCategoryInfo(title: "Games", rid: 1008),
                      RankCategoryInfo(title: "Knowledge", rid: 1010),
                      RankCategoryInfo(title: "Technology", rid: 1012),
                      RankCategoryInfo(title: "Sports", rid: 1018),
                      RankCategoryInfo(title: "Cars", rid: 1013),
                      RankCategoryInfo(title: "Lifestyle", rid: 160),
                      RankCategoryInfo(title: "Food", rid: 1020),
                      RankCategoryInfo(title: "Animals", rid: 1024),
                      RankCategoryInfo(title: "Meme", rid: 1007),
                      RankCategoryInfo(title: "Fashion", rid: 1014),
                      RankCategoryInfo(title: "Entertainment", rid: 1002),
                      RankCategoryInfo(title: "Series & Films", rid: 1001)]
}

class RankingViewController: CategoryViewController {
    override func viewDidLoad() {
        categories = RankCategoryInfo.all
            .map {
                if $0.isSeason {
                    return CategoryDisplayModel(title: $0.title, contentVC: RankingSeasonContentViewController(info: $0))
                } else {
                    return CategoryDisplayModel(title: $0.title, contentVC: RankingVideoContentViewController(info: $0))
                }
            }
        super.viewDidLoad()
    }
}

class RankingVideoContentViewController: StandardVideoCollectionViewController<VideoDetail.Info> {
    let info: RankCategoryInfo

    init(info: RankCategoryInfo) {
        self.info = info
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func setupCollectionView() {
        collectionVC.styleOverride = .sideBar
        super.setupCollectionView()
    }

    override func supportPullToLoad() -> Bool {
        return false
    }

    override func supportVideoQuickActions() -> Bool {
        return true
    }

    override func request(page: Int) async throws -> [VideoDetail.Info] {
        return try await WebRequest.requestRank(for: info.rid)
    }
}

class RankingSeasonContentViewController: StandardVideoCollectionViewController<Season> {
    let info: RankCategoryInfo
    init(info: RankCategoryInfo) {
        self.info = info
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func setupCollectionView() {
        collectionVC.styleOverride = .sideBar
        super.setupCollectionView()
    }

    override func supportPullToLoad() -> Bool {
        return false
    }

    override func request(page: Int) async throws -> [Season] {
        return try await WebRequest.requestSeasonRank(for: info.rid)
    }

    override func goDetail(with record: Season) {
        let detailVC = VideoDetailViewController.create(seasonId: record.season_id)
        detailVC.present(from: self)
    }
}

extension Season: PlayableData {
    var aid: Int { 0 }
    var cid: Int { 0 }
}

extension WebRequest.EndPoint {
    static let rank = "https://api.bilibili.com/x/web-interface/ranking/v2"
}

extension WebRequest {
    static func requestRank(for category: Int) async throws -> [VideoDetail.Info] {
        struct RankResp: Codable {
            let list: [VideoDetail.Info]
        }
        let resp: RankResp = try await request(url: EndPoint.rank, parameters: ["rid": category, "type": "all"])
        return resp.list
    }

    static func requestSeasonRank(for category: Int) async throws -> [Season] {
        struct Resp: Codable {
            let list: [Season]
        }
        let res: Resp = try await request(url: "https://api.bilibili.com/pgc/web/rank/list", parameters: ["day": 3, "season_type": category], dataObj: "result")
        return res.list
    }
}

struct Season: Codable, DisplayData {
    struct NewEP: Codable, Hashable {
        let cover: String
        let index_show: String
    }

    var ownerName: String { new_ep.index_show }
    var pic: URL? { cover }

    let title: String
    let cover: URL
    let season_id: Int
    let new_ep: NewEP
}
