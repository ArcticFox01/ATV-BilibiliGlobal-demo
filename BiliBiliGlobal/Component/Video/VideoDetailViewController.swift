//
//  VideoDetailViewController.swift
//  BiliBiliGlobal
//
//  Created by yicheng on 2021/4/17.
//

import AVKit
import Combine
import Foundation
import UIKit

import Alamofire
import Kingfisher
import MarqueeLabel
import SnapKit
import TVUIKit

private struct PageRange {
    let startIndex: Int
    let endIndex: Int

    var title: String {
        "\(startIndex + 1) - \(endIndex + 1)"
    }
}

class VideoDetailViewController: UIViewController {
    @IBOutlet var backgroundImageView: UIImageView!
    @IBOutlet var effectContainerView: UIVisualEffectView!
    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var upButton: BLCustomTextButton!
    @IBOutlet var followButton: BLCustomButton!
    @IBOutlet var coverImageView: UIImageView!
    @IBOutlet var playButton: BLCustomButton!
    @IBOutlet var likeButton: BLCustomButton!
    @IBOutlet var coinButton: BLCustomButton!
    @IBOutlet var noteView: NoteDetailView!
    @IBOutlet var dislikeButton: BLCustomButton!
    @IBOutlet var actionButtonSpaceView: UIView!
    @IBOutlet var durationLabel: UILabel!
    @IBOutlet var playCountLabel: UILabel!
    @IBOutlet var danmakuLabel: UILabel!
    @IBOutlet var uploadTimeLabel: UILabel!
    @IBOutlet var bvidLabel: UILabel!
    @IBOutlet var followersLabel: UILabel!
    @IBOutlet var avatarImageView: UIImageView!
    @IBOutlet var favButton: BLCustomButton!
    @IBOutlet var pageCollectionView: UICollectionView!
    @IBOutlet var recommandCollectionView: UICollectionView!
    @IBOutlet var replysCollectionView: UICollectionView!
    @IBOutlet var repliesCollectionViewHeightConstraints: NSLayoutConstraint!
    @IBOutlet var ugcCollectionView: UICollectionView!
    @IBOutlet var pageView: UIView!
    @IBOutlet var ugcLabel: UILabel!
    @IBOutlet var ugcView: UIView!

    private var loadingView = UIActivityIndicatorView()

    private var pageCollectionViewTopToTitleConstraint: Constraint?
    private var pageCollectionViewTopToRangeConstraint: Constraint?
    private let pageRangeSize = 20
    private var pageRanges = [PageRange]()
    private lazy var pageRangeCollectionView: UICollectionView = {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: makePageRangeCollectionViewLayout())
        collectionView.register(BLTextOnlyCollectionViewCell.self, forCellWithReuseIdentifier: String(describing: BLTextOnlyCollectionViewCell.self))
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.backgroundColor = .clear
        collectionView.clipsToBounds = false
        collectionView.isHidden = true
        return collectionView
    }()

    private var epid = 0
    private var seasonId = 0
    private var aid = 0
    private var cid = 0
    private var lastPlayCid: Int?
    private var lastPlayTitle: String?
    private var playTimeInSecond: Int?
    private var subType: Int?
    private var data: VideoDetail?
    @IBOutlet var scrollView: UIScrollView!
    private var didSentCoins = 0 {
        didSet {
            if didSentCoins > 0 {
                coinButton.isOn = true
            }
        }
    }

    private var isBangumi = false
    private var startTime = 0
    private var pages = [VideoPage]()
    private var episodeCovers = [Int: URL]()
    private var replys: Replys?
    private var subTitles: [SubtitleData]?

    private var allUgcEpisodes = [VideoDetail.Info.UgcSeason.UgcVideoInfo]()

    private var subscriptions = [AnyCancellable]()
    private var episodeProgressTask: Task<Void, Never>?

    deinit {
        episodeProgressTask?.cancel()
    }

    static func create(aid: Int, cid: Int?, epid: Int? = nil) -> VideoDetailViewController {
        let vc = UIStoryboard(name: "Main", bundle: .main).instantiateViewController(identifier: String(describing: self)) as! VideoDetailViewController
        vc.aid = aid
        vc.cid = cid ?? 0
        vc.epid = epid ?? 0
        return vc
    }

    static func create(epid: Int) -> VideoDetailViewController {
        let vc = UIStoryboard(name: "Main", bundle: .main).instantiateViewController(identifier: String(describing: self)) as! VideoDetailViewController
        vc.epid = epid
        return vc
    }

    static func create(seasonId: Int) -> VideoDetailViewController {
        let vc = UIStoryboard(name: "Main", bundle: .main).instantiateViewController(identifier: String(describing: self)) as! VideoDetailViewController
        vc.seasonId = seasonId
        return vc
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        pageCollectionView.register(BLTextOnlyCollectionViewCell.self, forCellWithReuseIdentifier: String(describing: BLTextOnlyCollectionViewCell.self))
        pageCollectionView.register(EpisodeThumbnailCell.self, forCellWithReuseIdentifier: String(describing: EpisodeThumbnailCell.self))
        pageCollectionView.collectionViewLayout = makePageCollectionViewLayout()
        pageCollectionView.clipsToBounds = false
        setupPageRangeCollectionView()
        recommandCollectionView.register(RelatedVideoCell.self, forCellWithReuseIdentifier: String(describing: RelatedVideoCell.self))
        ugcCollectionView.register(RelatedVideoCell.self, forCellWithReuseIdentifier: String(describing: RelatedVideoCell.self))
        recommandCollectionView.collectionViewLayout = makeRelatedVideoCollectionViewLayout()
        ugcCollectionView.collectionViewLayout = makeRelatedVideoCollectionViewLayout()
        noteView.onPrimaryAction = {
            [weak self] note in
            let detail = ContentDetailViewController.createDesp(content: note.label.text ?? "")
            self?.present(detail, animated: true)
        }

        var focusGuide = UIFocusGuide()
        view.addLayoutGuide(focusGuide)
        NSLayoutConstraint.activate([
            focusGuide.topAnchor.constraint(equalTo: upButton.topAnchor),
            focusGuide.leftAnchor.constraint(equalTo: followButton.rightAnchor),
            focusGuide.rightAnchor.constraint(equalTo: coverImageView.leftAnchor),
            focusGuide.bottomAnchor.constraint(equalTo: upButton.bottomAnchor),
        ])
        focusGuide.preferredFocusEnvironments = [followButton]

        focusGuide = UIFocusGuide()
        view.addLayoutGuide(focusGuide)
        NSLayoutConstraint.activate([
            focusGuide.topAnchor.constraint(equalTo: actionButtonSpaceView.topAnchor),
            focusGuide.leftAnchor.constraint(equalTo: actionButtonSpaceView.leftAnchor),
            focusGuide.rightAnchor.constraint(equalTo: actionButtonSpaceView.rightAnchor),
            focusGuide.bottomAnchor.constraint(equalTo: actionButtonSpaceView.bottomAnchor),
        ])
        focusGuide.preferredFocusEnvironments = [dislikeButton]

        replysCollectionView.publisher(for: \.contentSize).sink { [weak self] newSize in
            self?.repliesCollectionViewHeightConstraints.constant = newSize.height
            self?.view.setNeedsLayout()
        }.store(in: &subscriptions)

        NotificationCenter.default.publisher(for: EpisodeWatchStore.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateVisibleEpisodeProgress() }
            .store(in: &subscriptions)
        NotificationCenter.default.publisher(for: AccountManager.didUpdateNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateVisibleEpisodeProgress()
                self?.refreshEpisodeProgress()
            }.store(in: &subscriptions)

        Task { await fetchData() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateVisibleEpisodeProgress()
        refreshEpisodeProgress()
    }

    override var preferredFocusedView: UIView? {
        return playButton
    }

    private func setBangumiEpisodes(_ info: BangumiInfo, accountID: Int?) {
        pages = info.episodes.map { VideoPage(cid: $0.cid, page: $0.aid, epid: $0.id, from: "", part: $0.title + " " + $0.long_title) }
        episodeCovers.removeAll()
        for episode in info.episodes {
            episodeCovers[episode.id] = episode.cover
        }
        if AccountManager.shared.activeAccount?.profile.mid == accountID {
            importEpisodeProgress(info)
        }
    }

    private func importEpisodeProgress(_ info: BangumiInfo) {
        guard let progress = info.user_status?.progress,
              let episode = info.findEpisodeById(progress.last_ep_id) else { return }
        EpisodeWatchStore.shared.importProgress(episodeID: episode.id,
                                                accountID: AccountManager.shared.activeAccount?.profile.mid,
                                                position: progress.last_time, duration: Double(episode.duration ?? 0) / 1_000)
    }

    private func refreshEpisodeProgress() {
        episodeProgressTask?.cancel()
        guard isBangumi, data != nil, seasonId > 0 else { return }
        let requestedSeasonID = seasonId
        let accountID = AccountManager.shared.activeAccount?.profile.mid
        episodeProgressTask = Task { [weak self] in
            do {
                let info = try await WebRequest.requestBangumiInfo(seasonID: requestedSeasonID)
                guard let self, !Task.isCancelled, self.seasonId == requestedSeasonID,
                      AccountManager.shared.activeAccount?.profile.mid == accountID else { return }
                self.importEpisodeProgress(info)
                self.updateVisibleEpisodeProgress()
            } catch {
                // Retain locally known status when the server is unavailable.
                Logger.warn("Couldn't refresh episode watch progress: \(error.localizedDescription)")
            }
        }
    }

    private func updateVisibleEpisodeProgress() {
        guard isViewLoaded else { return }
        for case let cell as EpisodeThumbnailCell in pageCollectionView.visibleCells {
            guard let indexPath = pageCollectionView.indexPath(for: cell),
                  pages.indices.contains(indexPath.item), let episodeID = pages[indexPath.item].epid else { continue }
            cell.updateProgress(EpisodeWatchStore.shared.progress(for: episodeID,
                                                                  accountID: AccountManager.shared.activeAccount?.profile.mid))
        }
    }

    private func showEpisodeWatchOptions(_ page: VideoPage) {
        guard let episodeID = page.epid, let accountID = AccountManager.shared.activeAccount?.profile.mid else { return }
        let watched = EpisodeWatchStore.shared.progress(for: episodeID, accountID: accountID)?.isWatched == true
        let alert = UIAlertController(title: page.part, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: watched ? "Mark as Unwatched" : "Mark as Watched", style: .default) { _ in
            EpisodeWatchStore.shared.setWatched(!watched, episodeID: episodeID, accountID: accountID)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func updatePlayProgressIfNeeded(progress: BangumiInfo.UserStatus.Progress?, episode: BangumiInfo.Episode) {
        guard let lastEpId = progress?.last_ep_id,
              let lastTime = progress?.last_time,
              lastEpId == episode.id
        else {
            return
        }
        playTimeInSecond = lastTime
        lastPlayCid = episode.cid
        lastPlayTitle = episode.title + " " + episode.long_title
    }

    private func makeBangumiDetail(_ info: BangumiInfo) -> VideoDetail {
        let episode = info.findEpisodeById(epid) ?? info.episodes.first
        let stat = info.stat
        let view = VideoDetail.Info(
            aid: aid,
            cid: cid,
            title: info.title ?? info.season_title ?? episode?.title ?? "",
            videos: nil,
            pic: info.cover ?? episode?.cover,
            desc: info.evaluate,
            owner: VideoOwner(mid: 0, name: "BiliBili Global", face: nil),
            pages: nil,
            dynamic: nil,
            bvid: episode?.bvid,
            duration: (episode?.duration ?? 0) / 1_000,
            pubdate: episode?.pub_time,
            ugc_season: nil,
            redirect_url: nil,
            stat: VideoDetail.Info.Stat(
                favorite: stat?.favorites ?? stat?.favorite ?? 0,
                coin: stat?.coins ?? 0,
                like: stat?.likes ?? 0,
                share: stat?.share ?? 0,
                danmaku: stat?.danmakus ?? 0,
                view: stat?.views ?? 0
            )
        )
        return VideoDetail(
            View: view,
            Related: [],
            Card: VideoDetail.Owner(
                following: info.user_status?.follow == 1,
                follower: nil
            )
        )
    }

    private func setupPageRangeCollectionView() {
        let titleLabel = pageView.subviews.compactMap { $0 as? UILabel }.first { $0.text == "Episodes" }!

        pageView.addSubview(pageRangeCollectionView)

        let storyboardTopConstraints = pageView.constraints.filter { constraint in
            (constraint.firstItem as? UICollectionView) === pageCollectionView && constraint.firstAttribute == .top
        }
        storyboardTopConstraints.forEach { $0.isActive = false }

        let storyboardHeightConstraints = (pageView.constraints + pageCollectionView.constraints).filter { constraint in
            (constraint.firstItem as? UICollectionView) === pageCollectionView && constraint.firstAttribute == .height
        }
        storyboardHeightConstraints.forEach { $0.isActive = false }

        pageRangeCollectionView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.equalTo(titleLabel.snp.bottom).offset(30)
            make.height.equalTo(90)
        }
        pageCollectionView.snp.makeConstraints { make in
            pageCollectionViewTopToTitleConstraint = make.top.equalTo(titleLabel.snp.bottom).offset(30).constraint
            pageCollectionViewTopToRangeConstraint = make.top.equalTo(pageRangeCollectionView.snp.bottom).offset(30).constraint
            make.height.equalTo(150)
        }
        pageCollectionViewTopToRangeConstraint?.deactivate()
    }

    private func updatePageRanges() {
        guard pages.count >= pageRangeSize else {
            pageRanges = []
            setPageRangeCollectionViewHidden(true)
            return
        }

        pageRanges = stride(from: 0, to: pages.count, by: pageRangeSize).map { startIndex in
            PageRange(startIndex: startIndex, endIndex: min(startIndex + pageRangeSize, pages.count) - 1)
        }
        setPageRangeCollectionViewHidden(false)
    }

    private func setPageRangeCollectionViewHidden(_ isHidden: Bool) {
        pageRangeCollectionView.isHidden = isHidden
        if isHidden {
            pageCollectionViewTopToRangeConstraint?.deactivate()
            pageCollectionViewTopToTitleConstraint?.activate()
        } else {
            pageCollectionViewTopToTitleConstraint?.deactivate()
            pageCollectionViewTopToRangeConstraint?.activate()
        }
    }

    private func setupLoading() {
        effectContainerView.isHidden = true
        view.addSubview(loadingView)
        loadingView.color = .white
        loadingView.style = .large
        loadingView.startAnimating()
        loadingView.makeConstraintsBindToCenterOfSuperview()
    }

    func present(from vc: UIViewController, direatlyEnterVideo: Bool = Settings.direatlyEnterVideo) {
        if !direatlyEnterVideo {
            vc.present(self, animated: true)
        } else {
            vc.present(self, animated: false) { [weak self] in
                guard let self else { return }
                let player = VideoPlayerViewController(playInfo: PlayInfo(aid: self.aid, cid: self.cid, epid: self.epid, seasonId: isBangumi ? self.seasonId : nil, lastPlayCid: self.lastPlayCid, playTimeInSecond: self.playTimeInSecond))
                self.present(player, animated: true)
            }
        }
    }

    private func exit(with error: Error) {
        Logger.warn(error)
        let alertVC = UIAlertController(title: "Couldn't Load Video", message: error.localizedDescription, preferredStyle: .alert)
        alertVC.addAction(UIAlertAction(title: "Ok", style: .cancel, handler: { [weak self] action in
            self?.dismiss(animated: true)
        }))
        present(alertVC, animated: true, completion: nil)
    }

    private func fetchData() async {
        let accountID = AccountManager.shared.activeAccount?.profile.mid
        scrollView.setContentOffset(.zero, animated: false)
        setNeedsFocusUpdate()
        updateFocusIfNeeded()
        backgroundImageView.alpha = 0
        setupLoading()
        pageView.isHidden = true
        setPageRangeCollectionViewHidden(true)
        ugcView.isHidden = true
        do {
            var bangumiInfo: BangumiInfo?
            if seasonId > 0 {
                isBangumi = true
                let info = try await WebRequest.requestBangumiInfo(seasonID: seasonId)
                bangumiInfo = info
                subType = info.type
                if let epi = info.episodes.first(where: { $0.id == info.user_status?.progress?.last_ep_id }) ?? info.episodes.first ?? info.section?.first?.episodes.first {
                    aid = epi.aid
                    cid = epi.cid
                    epid = epi.id
                    updatePlayProgressIfNeeded(progress: info.user_status?.progress, episode: epi)
                }
                setBangumiEpisodes(info, accountID: accountID)
            } else if epid > 0 {
                isBangumi = true
                let info = try await WebRequest.requestBangumiInfo(epid: epid)
                bangumiInfo = info
                seasonId = info.season_id
                subType = info.type
                if let epi = info.findEpisodeById(epid) ?? info.episodes.first {
                    aid = epi.aid
                    cid = epi.cid
                    updatePlayProgressIfNeeded(progress: info.user_status?.progress, episode: epi)
                } else {
                    throw NSError(domain: "get epi fail", code: -1)
                }
                setBangumiEpisodes(info, accountID: accountID)
            }
            let data: VideoDetail
            if let bangumiInfo {
                data = makeBangumiDetail(bangumiInfo)
            } else {
                let detail = try await WebRequest.requestDetailVideo(aid: aid)
                if !isBangumi,
                   let redirect = detail.View.redirect_url?.lastPathComponent,
                   redirect.starts(with: "ep"),
                   let id = Int(redirect.dropFirst(2))
                {
                    isBangumi = true
                    epid = id
                    let info = try await WebRequest.requestBangumiInfo(epid: epid)
                    seasonId = info.season_id
                    subType = info.type
                    setBangumiEpisodes(info, accountID: accountID)
                    if let epi = info.episodes.first(where: { $0.id == epid }) {
                        updatePlayProgressIfNeeded(progress: info.user_status?.progress, episode: epi)
                    }
                    data = makeBangumiDetail(info)
                } else {
                    data = detail
                }
            }
            self.data = data
            if !isBangumi {
                let playInfo = try await WebRequest.requestPlayerInfo(aid: aid, cid: cid == 0 ? data.View.cid : cid)
                if cid == 0 {
                    cid = playInfo.last_play_cid > 0 ? playInfo.last_play_cid : data.View.cid
                }
                if playInfo.last_play_cid == cid, let page = data.View.pages?.first(where: { $0.cid == cid }) {
                    playTimeInSecond = playInfo.playTimeInSecond
                    lastPlayCid = playInfo.last_play_cid
                    lastPlayTitle = page.part
                }
            }
            update(with: data)
        } catch let err {
            self.exit(with: err)
        }

        WebRequest.requestReplys(aid: aid) { [weak self] replys in
            self?.replys = replys
            self?.replysCollectionView.reloadData()
        }

        WebRequest.requestLikeStatus(aid: aid) { [weak self] isLiked in
            self?.likeButton.isOn = isLiked
        }

        WebRequest.requestCoinStatus(aid: aid) { [weak self] coins in
            self?.didSentCoins = coins
        }

        if isBangumi {
            favButton.isHidden = true
            recommandCollectionView.superview?.isHidden = true
            return
        }

        WebRequest.requestFavoriteStatus(aid: aid) { [weak self] isFavorited in
            self?.favButton.isOn = isFavorited
        }
    }

    private func update(with data: VideoDetail) {
        playCountLabel.text = data.View.stat.view.numberString()
        danmakuLabel.text = data.View.stat.danmaku.numberString()
        followersLabel.text = (data.Card.follower ?? 0).numberString() + " followers"
        uploadTimeLabel.text = data.View.date
        bvidLabel.text = data.View.bvid
        coinButton.title = data.View.stat.coin.numberString()
        favButton.title = data.View.stat.favorite.numberString()
        likeButton.title = data.View.stat.like.numberString()

        durationLabel.text = data.View.durationString
        titleLabel.text = data.title
        upButton.title = data.ownerName
        followButton.isOn = data.Card.following

        // 更新播放按钮标题
        if Settings.continuePlay {
            if let lastPlayCid, lastPlayCid == cid {
                playButton.title = "Resume"
            } else {
                playButton.title = "Play"
            }
        }

        avatarImageView.kf.setImage(with: data.avatar(size: 240), options: [.processor(DownsamplingImageProcessor(size: CGSize(width: 80, height: 80))), .processor(RoundCornerImageProcessor(radius: .widthFraction(0.5))), .cacheSerializer(FormatIndicatedCacheSerializer.png)])

        coverImageView.kf.setImage(with: data.pic)
        backgroundImageView.kf.setImage(with: data.pic)
        recommandCollectionView.superview?.isHidden = data.Related.count == 0

        var notes = [String]()
        let status = data.View.dynamic ?? ""
        if status.count > 1, status != data.View.desc {
            notes.append(status)
        }
        notes.append(data.View.desc ?? "")
        noteView.label.text = notes.joined(separator: "\n")
        if !isBangumi {
            pages = data.View.pages ?? []
        }
        updatePageRanges()
        pageRangeCollectionView.reloadData()
        if pages.count > 1 {
            pageCollectionView.reloadData()
            pageView.isHidden = false
            let index = pages.firstIndex { $0.cid == cid } ?? 0
            pageCollectionView.scrollToItem(at: IndexPath(row: index, section: 0), at: .left, animated: false)
            if cid == 0 {
                cid = pages.first?.cid ?? 0
            }
        }
        loadingView.stopAnimating()
        loadingView.removeFromSuperview()
        effectContainerView.isHidden = false
        UIView.animate(withDuration: 0.25) {
            self.backgroundImageView.alpha = 1
        }

        if let season = data.View.ugc_season {
            if season.sections.count > 1 {
                if let section = season.sections.first(where: { section in section.episodes.contains(where: { episode in episode.aid == data.View.aid }) }) {
                    allUgcEpisodes = section.episodes
                }
            } else {
                allUgcEpisodes = season.sections.first?.episodes ?? []
            }
            allUgcEpisodes.sort { $0.arc.ctime < $1.arc.ctime }
        }

        ugcCollectionView.reloadData()
        ugcLabel.text = "Collection \(data.View.ugc_season?.title ?? "")  \(data.View.ugc_season?.sections.first?.title ?? "")"
        ugcView.isHidden = allUgcEpisodes.count == 0
        if allUgcEpisodes.count > 0 {
            ugcCollectionView.scrollToItem(at: IndexPath(item: allUgcEpisodes.map { $0.aid }.firstIndex(of: aid) ?? 0, section: 0), at: .left, animated: false)
        }

        recommandCollectionView.reloadData()
    }

    @IBAction func actionShowUpSpace(_ sender: Any) {
        let upSpaceVC = UpSpaceViewController()
        upSpaceVC.mid = data?.View.owner.mid
        present(upSpaceVC, animated: true)
    }

    @IBAction func actionFollow(_ sender: Any) {
        followButton.isOn.toggle()
        if let mid = data?.View.owner.mid {
            WebRequest.follow(mid: mid, follow: followButton.isOn)
        }
    }

    @IBAction func actionPlay(_ sender: Any) {
        let player = VideoPlayerViewController(playInfo: PlayInfo(aid: aid, cid: cid, epid: epid, seasonId: seasonId, subType: subType, lastPlayCid: lastPlayCid, playTimeInSecond: playTimeInSecond, title: data?.title))
        player.data = data
        if pages.count > 0, let index = pages.firstIndex(where: { $0.cid == cid }) {
            let seq = pages.map({ PlayInfo(aid: aid, cid: $0.cid, epid: $0.epid, seasonId: seasonId, subType: subType, title: $0.part) })
            if seq.count > 0 {
                player.sequenceProvider = VideoSequenceProvider(seq: seq, currentIndex: index)
            }
        }
        if allUgcEpisodes.count > 0, let index = allUgcEpisodes.firstIndex(where: { $0.cid == cid }) {
            let seq = allUgcEpisodes.map({ PlayInfo(aid: $0.aid, cid: $0.cid, title: $0.title) })
            if seq.count > 0 {
                player.sequenceProvider = VideoSequenceProvider(seq: seq, currentIndex: index)
            }
        }
        present(player, animated: true, completion: nil)
    }

    @IBAction func actionLike(_ sender: Any) {
        Task {
            if likeButton.isOn {
                likeButton.title? -= 1
            } else {
                likeButton.title? += 1
            }
            likeButton.isOn.toggle()
            let success = await WebRequest.requestLike(aid: aid, like: likeButton.isOn)
            if !success {
                likeButton.isOn.toggle()
            }
        }
    }

    @IBAction func actionCoin(_ sender: Any) {
        guard didSentCoins < 2 else { return }
        let alert = UIAlertController(title: "Coins", message: nil, preferredStyle: .actionSheet)
        WebRequest.requestTodayCoins { todayCoins in
            alert.message = "Coins sent today: \(todayCoins / 10)/5"
        }
        let aid = aid
        alert.addAction(UIAlertAction(title: "1", style: .default) { [weak self] _ in
            guard let self else { return }
            self.coinButton.title? += 1
            if !self.likeButton.isOn {
                self.likeButton.title? += 1
                self.likeButton.isOn = true
            }
            self.didSentCoins += 1
            WebRequest.requestCoin(aid: aid, num: 1)
        })
        if didSentCoins == 0 {
            alert.addAction(UIAlertAction(title: "2", style: .default) { [weak self] _ in
                guard let self else { return }
                self.coinButton.title? += 2
                if !self.likeButton.isOn {
                    self.likeButton.title? += 1
                    self.likeButton.isOn = true
                }
                self.likeButton.isOn = true
                self.didSentCoins += 2
                WebRequest.requestCoin(aid: aid, num: 2)
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    @IBAction func actionFavorite(_ sender: Any) {
        Task {
            guard let favList = try? await WebRequest.requestFavVideosList() else {
                return
            }
            if favButton.isOn {
                favButton.title? -= 1
                favButton.isOn = false
                WebRequest.removeFavorite(aid: aid, mid: favList.map { $0.id })
                return
            }
            let alert = UIAlertController(title: "Favorites", message: nil, preferredStyle: .actionSheet)
            let aid = aid
            for fav in favList {
                alert.addAction(UIAlertAction(title: fav.title, style: .default) { [weak self] _ in
                    self?.favButton.title? += 1
                    self?.favButton.isOn = true
                    WebRequest.requestFavorite(aid: aid, mid: fav.id)
                })
            }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            present(alert, animated: true)
        }
    }

    @IBAction func actionDislike(_ sender: Any) {
        dislikeButton.isOn.toggle()
        ApiRequest.requestDislike(aid: aid, dislike: dislikeButton.isOn)
    }
}

extension VideoDetailViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        switch collectionView {
        case pageRangeCollectionView:
            let range = pageRanges[indexPath.item]
            pageCollectionView.scrollToItem(at: IndexPath(item: range.startIndex, section: 0), at: .left, animated: true)
        case pageCollectionView:
            let page = pages[indexPath.item]
            let player = VideoPlayerViewController(playInfo: PlayInfo(aid: isBangumi ? page.page : aid, cid: page.cid, epid: page.epid, seasonId: seasonId, subType: subType, lastPlayCid: lastPlayCid, playTimeInSecond: playTimeInSecond, title: page.part))
            player.data = isBangumi ? nil : data

            let seq = pages.map({ PlayInfo(aid: isBangumi ? $0.page : aid, cid: $0.cid, epid: $0.epid, seasonId: seasonId, subType: subType, title: $0.part) })
            if seq.count > 0 {
                player.sequenceProvider = VideoSequenceProvider(seq: seq, currentIndex: indexPath.item)
            }
            present(player, animated: true, completion: nil)
        case replysCollectionView:
            guard let reply = replys?.replies?[indexPath.item] else { return }
            let detail = ReplyDetailViewController(reply: reply)
            present(detail, animated: true)
        case ugcCollectionView:
            let video = allUgcEpisodes[indexPath.item]
            if Settings.showRelatedVideoInCurrentVC {
                aid = video.aid
                cid = video.cid
                Task { await fetchData() }
            } else {
                let detailVC = VideoDetailViewController.create(aid: video.aid, cid: video.cid)
                detailVC.present(from: self)
            }
        case recommandCollectionView:
            if let video = data?.Related[indexPath.item] {
                if Settings.showRelatedVideoInCurrentVC {
                    aid = video.aid
                    cid = video.cid
                    Task { await fetchData() }
                } else {
                    let detailVC = VideoDetailViewController.create(aid: video.aid, cid: video.cid)
                    detailVC.present(from: self)
                }
            }
        default:
            break
        }
    }
}

extension VideoDetailViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        switch collectionView {
        case pageRangeCollectionView:
            return pageRanges.count
        case pageCollectionView:
            return pages.count
        case replysCollectionView:
            return replys?.replies?.count ?? 0
        case ugcCollectionView:
            return allUgcEpisodes.count
        case recommandCollectionView:
            return data?.Related.count ?? 0
        default:
            return 0
        }
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        switch collectionView {
        case pageRangeCollectionView:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "BLTextOnlyCollectionViewCell", for: indexPath) as! BLTextOnlyCollectionViewCell
            cell.titleLabel.text = pageRanges[indexPath.item].title
            return cell
        case pageCollectionView:
            let page = pages[indexPath.item]
            if let epid = page.epid {
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "EpisodeThumbnailCell", for: indexPath) as! EpisodeThumbnailCell
                cell.configure(title: page.part, cover: episodeCovers[epid],
                               progress: EpisodeWatchStore.shared.progress(for: epid, accountID: AccountManager.shared.activeAccount?.profile.mid))
                cell.onLongPress = { [weak self] in self?.showEpisodeWatchOptions(page) }
                return cell
            }
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "BLTextOnlyCollectionViewCell", for: indexPath) as! BLTextOnlyCollectionViewCell
            cell.titleLabel.text = page.part
            return cell
        case replysCollectionView:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: String(describing: ReplyCell.self), for: indexPath) as! ReplyCell
            if let reply = replys?.replies?[indexPath.item] {
                cell.config(replay: reply)
            }
            return cell
        case ugcCollectionView:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: String(describing: RelatedVideoCell.self), for: indexPath) as! RelatedVideoCell
            let record = allUgcEpisodes[indexPath.row]
            cell.update(data: record)
            return cell
        case recommandCollectionView:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: String(describing: RelatedVideoCell.self), for: indexPath) as! RelatedVideoCell
            if let related = data?.Related[indexPath.row] {
                cell.update(data: related)
            }
            return cell
        default:
            return UICollectionViewCell()
        }
    }
}

class BLCardView: TVCardView {
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        subviews.first?.subviews.first?.subviews.last?.subviews.first?.subviews.first?.layer.cornerRadius = 12
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        cardBackgroundColor = UIColor(named: "bgColor")
    }
}

extension VideoDetailViewController {
    func makePageCollectionViewLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout {
            _, _ in
            let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                                  heightDimension: .fractionalHeight(1.0))
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            let groupSize = NSCollectionLayoutSize(widthDimension: .absolute(300), heightDimension: .absolute(150))
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
            let section = NSCollectionLayoutSection(group: group)
            section.orthogonalScrollingBehavior = .continuous
            section.interGroupSpacing = 40
            return section
        }
    }

    func makePageRangeCollectionViewLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout {
            _, _ in
            let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                                  heightDimension: .fractionalHeight(1.0))
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            let groupSize = NSCollectionLayoutSize(widthDimension: .absolute(200), heightDimension: .fractionalHeight(1))
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
            let section = NSCollectionLayoutSection(group: group)
            section.orthogonalScrollingBehavior = .continuous
            section.interGroupSpacing = 40
            return section
        }
    }

    func makeRelatedVideoCollectionViewLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout {
            _, _ in
            let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                                  heightDimension: .estimated(200))
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(0.18), heightDimension: .estimated(200))
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets = .init(top: 40, leading: 0, bottom: 0, trailing: 0)
            section.orthogonalScrollingBehavior = .continuous
            section.interGroupSpacing = 40
            return section
        }
    }
}

private class EpisodeThumbnailCell: BLMotionCollectionViewCell {
    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    private let gradient = CAGradientLayer()
    private let watchedBadge = UIStackView()
    private let progressView = UIProgressView(progressViewStyle: .default)
    var onLongPress: (() -> Void)?

    override func setup() {
        super.setup()
        scaleFactor = 1.15
        contentView.backgroundColor = .darkGray
        contentView.layer.cornerRadius = 16
        contentView.clipsToBounds = true
        imageView.contentMode = .scaleAspectFill
        contentView.addSubview(imageView)
        imageView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        gradient.colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.85).cgColor]
        contentView.layer.addSublayer(gradient)
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 24, weight: .medium)
        titleLabel.numberOfLines = 2
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(12)
            make.bottom.equalToSuperview().inset(24)
        }

        let checkmark = UIImageView(image: UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)))
        checkmark.tintColor = .white
        checkmark.contentMode = .scaleAspectFit
        let watchedLabel = UILabel()
        watchedLabel.text = "Watched"
        watchedLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        watchedLabel.textColor = .white
        watchedBadge.addArrangedSubview(checkmark)
        watchedBadge.addArrangedSubview(watchedLabel)
        watchedBadge.spacing = 6
        watchedBadge.alignment = .center
        watchedBadge.isLayoutMarginsRelativeArrangement = true
        watchedBadge.layoutMargins = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        watchedBadge.backgroundColor = UIColor.black.withAlphaComponent(0.85)
        watchedBadge.layer.cornerRadius = 8
        watchedBadge.isUserInteractionEnabled = false
        contentView.addSubview(watchedBadge)
        watchedBadge.snp.makeConstraints { make in
            make.top.trailing.equalToSuperview().inset(12)
        }

        progressView.progressTintColor = .white
        progressView.trackTintColor = UIColor.white.withAlphaComponent(0.35)
        progressView.isUserInteractionEnabled = false
        contentView.addSubview(progressView)
        progressView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(12)
            make.bottom.equalToSuperview().inset(10)
            make.height.equalTo(4)
        }
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityHint = "Press and hold for watch options."
        addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:))))
        updateProgress(nil)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = contentView.bounds
    }

    func configure(title: String, cover: URL?, progress: EpisodeWatchProgress?) {
        titleLabel.text = title
        accessibilityLabel = title
        updateProgress(progress)
        imageView.kf.setImage(with: cover, options: [.processor(DownsamplingImageProcessor(size: CGSize(width: 360, height: 202))), .cacheOriginalImage])
    }

    func updateProgress(_ progress: EpisodeWatchProgress?) {
        let watched = progress?.isWatched == true
        let fraction = progress?.fraction ?? 0
        watchedBadge.isHidden = !watched
        progressView.isHidden = watched || fraction <= 0
        progressView.progress = fraction
        accessibilityValue = watched ? "Watched" : fraction > 0 ? "\(Int(fraction * 100))% watched" : "Not watched"
    }

    @objc private func longPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        onLongPress?()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.kf.cancelDownloadTask()
        imageView.image = nil
        onLongPress = nil
        accessibilityLabel = nil
        updateProgress(nil)
    }
}

class RelatedVideoCell: BLMotionCollectionViewCell {
    let titleLabel = MarqueeLabel()
    let imageView = UIImageView()
    override func setup() {
        super.setup()
        contentView.addSubview(imageView)
        contentView.addSubview(titleLabel)
        imageView.snp.makeConstraints { make in
            make.top.left.right.equalToSuperview()
            make.width.equalTo(imageView.snp.height).multipliedBy(14.0 / 9)
        }
        imageView.layer.cornerRadius = 12
        imageView.clipsToBounds = true
        imageView.contentMode = .scaleAspectFill
        titleLabel.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalTo(imageView.snp.bottom).offset(6)
        }
        titleLabel.setContentHuggingPriority(.required, for: .vertical)
        titleLabel.font = UIFont.systemFont(ofSize: 28)
        titleLabel.fadeLength = 60
        stopScroll()
    }

    func update(data: any DisplayData) {
        titleLabel.text = data.title
        imageView.kf.setImage(with: data.pic, options: [.processor(DownsamplingImageProcessor(size: CGSize(width: 360, height: 202))), .cacheOriginalImage])
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        if isFocused {
            startScroll()
        } else {
            stopScroll()
        }
    }

    private func startScroll() {
        titleLabel.restartLabel()
        titleLabel.holdScrolling = false
    }

    private func stopScroll() {
        titleLabel.shutdownLabel()
        titleLabel.holdScrolling = true
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        stopScroll()
    }
}

class DetailLabel: UILabel {
    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        coordinator.addCoordinatedAnimations {
            if self.isFocused {
                self.backgroundColor = .white
            } else {
                self.backgroundColor = .clear
            }
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        isUserInteractionEnabled = true
    }

    override var canBecomeFocused: Bool {
        return true
    }

    override func drawText(in rect: CGRect) {
        let insets = UIEdgeInsets(top: 0, left: 5, bottom: 0, right: 5)
        super.drawText(in: rect.inset(by: insets))
    }
}

class NoteDetailView: UIControl {
    let label = UILabel()
    var onPrimaryAction: ((NoteDetailView) -> Void)?
    private let backgroundView = UIView()
    init() {
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func setup() {
        addSubview(backgroundView)
        backgroundView.backgroundColor = UIColor(named: "bgColor")
        backgroundView.layer.shadowOffset = CGSizeMake(0, 10)
        backgroundView.layer.shadowOpacity = 0.15
        backgroundView.layer.shadowRadius = 16.0
        backgroundView.layer.cornerRadius = 20
        backgroundView.layer.cornerCurve = .continuous
        backgroundView.isHidden = !isFocused
        backgroundView.snp.makeConstraints { make in
            make.top.bottom.equalToSuperview()
            make.left.equalToSuperview().offset(-20)
            make.right.equalToSuperview().offset(20)
        }

        addSubview(label)
        label.numberOfLines = 0
        label.font = UIFont.systemFont(ofSize: 29)
        label.textColor = UIColor(named: "titleColor")
        label.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.equalToSuperview().offset(14)
            make.bottom.lessThanOrEqualToSuperview().offset(-14)
        }
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        backgroundView.isHidden = !isFocused
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        super.pressesEnded(presses, with: event)
        if presses.first?.type == .select {
            sendActions(for: .primaryActionTriggered)
            onPrimaryAction?(self)
        }
    }
}

class ContentDetailViewController: UIViewController {
    private let titleLabel = UILabel()
    private let contentTextView = UITextView()

    static func createDesp(content: String) -> ContentDetailViewController {
        let vc = ContentDetailViewController()
        vc.titleLabel.text = "Description"
        vc.contentTextView.text = content
        return vc
    }

    static func createReply(content: String) -> ContentDetailViewController {
        let vc = ContentDetailViewController()
        vc.titleLabel.text = "Comments"
        vc.contentTextView.text = content
        return vc
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        [contentTextView]
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(titleLabel)
        view.addSubview(contentTextView)
        titleLabel.font = UIFont.systemFont(ofSize: 60, weight: .semibold)
        titleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(80)
            make.centerX.equalToSuperview()
        }
        contentTextView.panGestureRecognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
        contentTextView.isScrollEnabled = true
        contentTextView.isUserInteractionEnabled = true
        contentTextView.isSelectable = true
        contentTextView.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom)
            make.centerX.equalToSuperview()
            make.leading.equalToSuperview().offset(60)
            make.trailing.equalToSuperview().inset(60)
            make.bottom.equalToSuperview().inset(80)
        }
    }
}
