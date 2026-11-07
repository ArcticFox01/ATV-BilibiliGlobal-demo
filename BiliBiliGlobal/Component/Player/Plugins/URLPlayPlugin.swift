//
//  URLPlayPlugin.swift
//  BiliBiliGlobal
//
//  Created by yicheng on 2024/6/6.
//

import AVKit
import Foundation

class URLPlayPlugin: NSObject {
    var onPlayFail: (() -> Void)?
    var externalMetadata: [AVMetadataItem]?

    private weak var playerVC: AVPlayerViewController?
    private let referer: String
    private let isLive: Bool
    private var currentUrl: String?
    private var startupTimeout: DispatchWorkItem?
    private var readinessObservation: NSKeyValueObservation?

    init(referer: String = "", isLive: Bool = false) {
        self.referer = referer
        self.isLive = isLive
    }

    func play(urlString: String) {
        startupTimeout?.cancel()
        readinessObservation = nil
        currentUrl = urlString
        let headers: [String: String] = [
            // Live CDN URLs are issued for web playback and reject the app-branded
            // Global user agent used by ordinary API calls.
            "User-Agent": isLive ? Keys.liveUserAgent : Keys.userAgent,
            "Referer": referer,
        ]
        let asset = AVURLAsset(url: URL(string: urlString)!, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let playerItem = AVPlayerItem(asset: asset)
        if let externalMetadata {
            playerItem.externalMetadata = externalMetadata
        }
        let player = AVPlayer(playerItem: playerItem)
        player.automaticallyWaitsToMinimizeStalling = !isLive
        playerVC?.player = player

        guard isLive else { return }
        let timeout = DispatchWorkItem { [weak self] in
            self?.onPlayFail?()
        }
        startupTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: timeout)

        // A quality switch can become ready before the container observes it.
        // Include the current status so the replacement always starts playing.
        readinessObservation = playerItem.observe(\.status, options: [.initial, .new]) { [weak self, weak player] item, _ in
            guard item.status == .readyToPlay else { return }
            DispatchQueue.main.async { [weak self, weak player] in
                guard let self, let player,
                      self.readinessObservation != nil,
                      self.playerVC?.player === player,
                      player.currentItem?.status == .readyToPlay
                else { return }
                player.play()
            }
        }
    }
}

extension URLPlayPlugin: CommonPlayerPlugin {
    func playerDidLoad(playerVC: AVPlayerViewController) {
        self.playerVC = playerVC
        playerVC.requiresLinearPlayback = isLive
        playerVC.player = nil
        if let currentUrl {
            play(urlString: currentUrl)
        }
    }

    func playerDidFail(player: AVPlayer) {
        startupTimeout?.cancel()
        onPlayFail?()
    }

    func playerDidStart(player: AVPlayer) {
        startupTimeout?.cancel()
    }

    func playerDidStall(player: AVPlayer) {
        guard isLive else { return }
        startupTimeout?.cancel()
        onPlayFail?()
    }

    func playerDidCleanUp(player: AVPlayer) {
        startupTimeout?.cancel()
        readinessObservation = nil
    }
}
