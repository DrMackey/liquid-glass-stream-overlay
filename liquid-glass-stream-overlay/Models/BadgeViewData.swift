//
//  EmoteModel.swift
//  liquid-glass-stream-overlay
//
//  Created by Rodney Mackey on 04.11.2025.
//

import Foundation

struct BadgeViewData: Identifiable, Hashable, Equatable {
    let id = UUID()
    let set: String
    let version: String
    let url: URL?
}

struct BadgeInfo: Hashable {
    let set: String
    let version: String
    let imageUrl: String
}
