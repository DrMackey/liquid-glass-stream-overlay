//
//  EmoteModel.swift
//  liquid-glass-stream-overlay
//
//  Created by Rodney Mackey on 04.11.2025.
//

import Foundation
import SwiftUI

// MARK: - DisplayMessage
struct DisplayMessage: Identifiable {
    let id = UUID()
    let badges: [BadgeViewData]
    let sender: String
    let senderColor: Color
    let visibleParts: [MessagePart]
    let isTruncated: Bool
}
