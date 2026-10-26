//
//  Keys.swift
//  BilibiliLive
//
//  Created by yicheng on 2024/5/13.
//

import Foundation

enum Keys {
    static let userAgent = "Bilibili Global for Apple TV/1.0"
    static let liveReferer = "https://live.bilibili.com"
    static let webBaseURL = "https://www.bilibili.com/en"
    static let referer = webBaseURL
    static func referer(for aid: Int) -> String {
        return "\(webBaseURL)/video/av\(aid)"
    }
}
