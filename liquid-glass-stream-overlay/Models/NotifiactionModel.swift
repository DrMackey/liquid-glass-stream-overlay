//
//  NotifiactionModel.swift
//  liquid-glass-stream-overlay
//
//  Created by Rodney Mackey on 01.11.2025.
//

import Foundation
import SwiftUI

/// Single model representing the structure of the provided JSON.
/// Decoding/encoding is intentionally omitted per request.
struct NotificationMessage: Sendable {
    var metadata: Metadata
    var payload: Payload

    struct Metadata: Sendable {
        var message_id: String
        var message_type: String
        var message_timestamp: String
    }

    struct Payload: Sendable {
        var session: Session
    }

    struct Session: Sendable {
        var id: String
        var status: String
        var connected_at: String
        var keepalive_timeout_seconds: Int
        var reconnect_url: String? // keep as String? to avoid decoding concerns
    }
}

struct Notification: Equatable, Identifiable {
    let id: UUID
    let sender: String
    let text: String
    let badges: [(String, String)]
    let senderColor: Color?
    let badgeViewData: [BadgeViewData]

    static func == (lhs: Notification, rhs: Notification) -> Bool {
        lhs.id == rhs.id &&
        lhs.sender == rhs.sender &&
        lhs.text == rhs.text &&
        lhs.badges.elementsEqual(rhs.badges, by: { $0.0 == $1.0 && $0.1 == $1.1 }) &&
        lhs.senderColor == rhs.senderColor &&
        lhs.badgeViewData == rhs.badgeViewData
    }
}
