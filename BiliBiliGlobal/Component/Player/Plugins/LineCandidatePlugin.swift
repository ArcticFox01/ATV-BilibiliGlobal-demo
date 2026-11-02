//
//  LineCandidatePlugin.swift
//  BiliBiliGlobal
//

import AVKit
import UIKit

class LineCandidatesPlugin: NSObject, CommonPlayerPlugin {
    private weak var playerVC: AVPlayerViewController?
    private var candidates: [LivePlayUrlInfo]
    private var qualities: [LiveQuality]
    private var onQualityChange: ((Int) -> Void)?
    private var currentUrl: String?
    private var onLineCandidateChange: ((LivePlayUrlInfo) -> Void)?

    init(candidates: [LivePlayUrlInfo], qualities: [LiveQuality],
         onLineCandidateChange: @escaping (LivePlayUrlInfo) -> Void,
         onQualityChange: @escaping (Int) -> Void)
    {
        self.candidates = candidates
        self.qualities = qualities
        self.onQualityChange = onQualityChange
        self.onLineCandidateChange = onLineCandidateChange
        super.init()
    }

    func update(candidates: [LivePlayUrlInfo], qualities: [LiveQuality]) {
        self.candidates = candidates
        self.qualities = qualities
    }

    func playerDidLoad(playerVC: AVPlayerViewController) {
        self.playerVC = playerVC
    }

    func addMenuItems(current: inout [UIMenuElement]) -> [UIMenuElement] {
        guard !candidates.isEmpty else {
            return []
        }

        if let urlAsset = playerVC?.player?.currentItem?.asset as? AVURLAsset {
            currentUrl = urlAsset.url.absoluteString
        }

        let currentQuality = (candidates.first { $0.url == currentUrl } ?? candidates.first)?.current_qn
        let qualityActions = qualities.map { quality in
            UIAction(title: quality.displayName, state: currentQuality == quality.qn ? .on : .off) { [weak self] _ in
                self?.onQualityChange?(quality.qn)
            }
        }
        let routeActions = candidates.enumerated().map { idx, info in
            let quality = qualities.first { $0.qn == info.current_qn }?.displayName ?? "Unknown quality"
            let title = "#\(idx + 1) \(quality) · \(info.formate ?? ""), \(info.codec_name ?? "")"
            return UIAction(title: title, state: self.currentUrl == info.url ? .on : .off) { [weak self] _ in
                self?.onLineCandidateChange?(info)
            }
        }
        let qualityMenu = UIMenu(title: "Quality", options: [.displayInline, .singleSelection], children: qualityActions)
        let routeMenu = UIMenu(title: "Stream Route", options: [.displayInline, .singleSelection], children: routeActions)
        return [UIMenu(title: "Video Quality", image: UIImage(systemName: "video.fill"),
                       children: [qualityMenu, routeMenu])]
    }
}
