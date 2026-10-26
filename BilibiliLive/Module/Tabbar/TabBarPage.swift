//
//  TabBarPage.swift
//  BilibiliLive
//

import Foundation
import UIKit

enum TabBarPage: String, CaseIterable, Codable {
    case live
    case feed
    case hot
    case ranking
    case follows
    case favorite
    case personal
    case search
    case followBangumi
    case followUps
    case toView
    case history
    case weeklyWatch
    case tvRecommend

    var title: String {
        switch self {
        case .live:
            return "Live"
        case .feed:
            return "For You"
        case .tvRecommend:
            return "TV Picks"
        case .hot:
            return "Trending"
        case .ranking:
            return "Rankings"
        case .follows:
            return "Following"
        case .favorite:
            return "Favorites"
        case .personal:
            return "Profile"
        case .search:
            return "Search"
        case .followBangumi:
            return "Shows"
        case .followUps:
            return "Creators"
        case .toView:
            return "Watch Later"
        case .history:
            return "History"
        case .weeklyWatch:
            return "Weekly Picks"
        }
    }

    var isFixedInTabBar: Bool {
        self == .personal
    }

    var requirePresentInPersonalPage: Bool {
        switch self {
        case .favorite, .search, .followBangumi, .tvRecommend:
            return true
        default:
            return false
        }
    }

    static var defaultTabBarPages: [TabBarPage] {
        [.live, .feed, .hot, .ranking, .follows, .favorite, .personal, .search]
    }

    static var allConfigurablePages: [TabBarPage] {
        return allCases
    }
}
