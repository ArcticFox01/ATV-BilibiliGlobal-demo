//
//  LiveStatisticsPlugin.swift
//  BiliBiliGlobal
//

import AVKit
import UIKit

final class LiveStatisticsPlugin: NSObject, CommonPlayerPlugin {
    private let roomID: Int
    private let watchedBadge = LiveCountBadgeView(symbol: "person.2", name: "Watching")
    private let likesBadge = LiveCountBadgeView(symbol: "hand.thumbsup", name: "Likes")
    private let countRow = UIStackView()
    private let infoBackground = makeLiveBadgeBackground()
    private weak var playerViewController: AVPlayerViewController?
    private var refreshTask: Task<Void, Never>?
    private var watchedRevision = 0
    private var likesRevision = 0
    private var watchedCount: Int?
    private var likeCount: Int?

    init(roomID: Int) {
        self.roomID = roomID
        super.init()
        countRow.axis = .horizontal
        countRow.spacing = 24
        countRow.isUserInteractionEnabled = false
        countRow.alpha = 0
        countRow.addArrangedSubview(watchedBadge)
        countRow.addArrangedSubview(likesBadge)
    }

    deinit {
        refreshTask?.cancel()
    }

    func playerDidLoad(playerVC: AVPlayerViewController) {
        playerViewController = playerVC
        if #available(tvOS 26.6, *), infoBackground.superview == nil, let overlay = playerVC.contentOverlayView {
            // The native bare Info title on Living Room (tvOS 26.6.1) is inset
            // from the safe-area edge. Its visible center was measured 6 points
            // right and below the original backdrop in the device photo.
            let titleWidth = ("Info" as NSString).size(withAttributes: [
                .font: UIFont.systemFont(ofSize: 28, weight: .semibold),
            ]).width
            overlay.addSubview(infoBackground)
            infoBackground.snp.makeConstraints { make in
                make.centerX.equalTo(playerVC.view.safeAreaLayoutGuide.snp.leading).offset(titleWidth / 2 + 6)
                make.bottom.equalTo(playerVC.view.snp.bottom).offset(-38)
                make.width.equalTo(108)
                make.height.equalTo(64)
            }
        }
        if countRow.superview == nil {
            playerVC.view.addSubview(countRow)
            countRow.snp.makeConstraints { make in
                if infoBackground.superview != nil {
                    make.leading.equalTo(infoBackground.snp.trailing).offset(24)
                    make.centerY.equalTo(infoBackground)
                } else {
                    make.leading.equalTo(playerVC.view.safeAreaLayoutGuide.snp.leading).offset(130)
                    make.bottom.equalToSuperview().offset(-44)
                }
                make.trailing.lessThanOrEqualTo(playerVC.view.safeAreaLayoutGuide.snp.trailing)
            }
        }
        if let overlay = playerVC.contentOverlayView {
            watchedBadge.attachBackground(to: overlay)
            likesBadge.attachBackground(to: overlay)
        }
        guard refreshTask == nil else { return }
        let roomID = roomID
        refreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let watchedRevision = self?.watchedRevision
                let likesRevision = self?.likesRevision
                if let info = try? await WebRequest.requestLiveStatistics(roomID: roomID) {
                    guard !Task.isCancelled else { return }
                    // A room event received during the request is newer than this snapshot.
                    self?.update(watchedCount: self?.watchedRevision == watchedRevision ? info.watched_show?.num : nil,
                                 likeCount: self?.likesRevision == likesRevision ? info.like_info_v3?.total_likes : nil)
                }
                do {
                    try await Task.sleep(nanoseconds: 60_000_000_000)
                } catch {
                    return
                }
            }
        }
    }

    func playerWillCleanUp(playerVC: AVPlayerViewController) {
        refreshTask?.cancel()
        refreshTask = nil
        playerViewController = nil
        countRow.removeFromSuperview()
        infoBackground.removeFromSuperview()
        watchedBadge.removeBackground()
        likesBadge.removeBackground()
    }

    func playerTransportBarVisibilityDidChange(isVisible: Bool) {
        if isVisible {
            playerViewController?.view.bringSubviewToFront(countRow)
        }
        countRow.alpha = isVisible ? 1 : 0
        infoBackground.isHidden = !isVisible
        watchedBadge.setControlsVisible(isVisible)
        likesBadge.setControlsVisible(isVisible)
    }

    func update(watchedCount: Int?, likeCount: Int?) {
        if let watchedCount, watchedCount >= 0 {
            watchedRevision += 1
            self.watchedCount = watchedCount
        }
        if let likeCount, likeCount >= 0 {
            likesRevision += 1
            self.likeCount = likeCount
        }
        watchedBadge.update(count: self.watchedCount)
        likesBadge.update(count: self.likeCount)
    }
}

private func makeLiveBadgeBackground() -> UIVisualEffectView {
    let background = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    background.layer.cornerRadius = 32
    background.clipsToBounds = true
    background.isUserInteractionEnabled = false
    background.isHidden = true
    return background
}

private final class LiveCountBadgeView: UIView {
    private let valueLabel = UILabel()
    private let backgroundView = makeLiveBadgeBackground()
    private let name: String
    private var controlsAreVisible = false

    init(symbol: String, name: String) {
        self.name = name
        super.init(frame: .zero)
        isHidden = true
        isAccessibilityElement = true

        let imageView = UIImageView(image: UIImage(systemName: symbol,
                                                   withConfiguration: UIImage.SymbolConfiguration(pointSize: 28, weight: .regular)))
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFit
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 28, weight: .medium)
        valueLabel.textColor = .white
        let content = UIStackView(arrangedSubviews: [imageView, valueLabel])
        content.alignment = .center
        content.spacing = 8
        addSubview(content)
        content.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(24)
            make.centerY.equalToSuperview()
        }
        snp.makeConstraints { $0.height.equalTo(64) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func attachBackground(to overlay: UIView) {
        guard backgroundView.superview == nil else { return }
        // Keep all capsule materials below AVKit's controls; only the foreground
        // icons and counts fade, so blur views never inherit a partial alpha.
        overlay.addSubview(backgroundView)
        backgroundView.snp.makeConstraints { $0.edges.equalTo(self) }
    }

    func removeBackground() {
        backgroundView.removeFromSuperview()
    }

    func setControlsVisible(_ visible: Bool) {
        controlsAreVisible = visible
        backgroundView.isHidden = !visible || isHidden
    }

    func update(count: Int?) {
        guard let count else { return }
        isHidden = false
        backgroundView.isHidden = !controlsAreVisible
        valueLabel.text = count.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
        accessibilityLabel = "\(count.formatted()) \(name)"
    }
}

extension WebRequest {
    struct LiveStatistics: Codable, Hashable {
        struct Watched: Codable, Hashable {
            let num: Int?
        }

        struct Likes: Codable, Hashable {
            let total_likes: Int?
        }

        let watched_show: Watched?
        let like_info_v3: Likes?
    }

    static func requestLiveStatistics(roomID: Int) async throws -> LiveStatistics {
        try await request(url: "https://api.live.bilibili.com/xlive/web-room/v1/index/getInfoByRoom",
                          parameters: ["room_id": roomID])
    }
}
