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

    private weak var playerVC: AVPlayerViewController?
    private let referer: String
    private let isLive: Bool
    private var currentUrl: String?
    private var startupTimeout: DispatchWorkItem?

    init(referer: String = "", isLive: Bool = false) {
        self.referer = referer
        self.isLive = isLive
    }

    func play(urlString: String) {
        startupTimeout?.cancel()
        currentUrl = urlString
        let headers: [String: String] = [
            // Live CDN URLs are issued for web playback and reject the app-branded
            // Global user agent used by ordinary API calls.
            "User-Agent": isLive ? Keys.liveUserAgent : Keys.userAgent,
            "Referer": referer,
        ]
        let asset = AVURLAsset(url: URL(string: urlString)!, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let playerItem = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: playerItem)
        player.automaticallyWaitsToMinimizeStalling = !isLive
        playerVC?.player = player

        guard isLive else { return }
        let timeout = DispatchWorkItem { [weak self] in
            self?.onPlayFail?()
        }
        startupTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: timeout)
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
    }
}
