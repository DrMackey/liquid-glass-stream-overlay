import SwiftUI

// MARK: - Цвет из HEX
extension TwitchChatManager {
    func colorFromHex(_ hex: String) -> Color {
        let hexSanitized = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
        if hexSanitized.count == 3 {
            let r = String(repeating: hexSanitized[hexSanitized.startIndex], count: 2)
            let g = String(repeating: hexSanitized[hexSanitized.index(hexSanitized.startIndex, offsetBy: 1)], count: 2)
            let b = String(repeating: hexSanitized[hexSanitized.index(hexSanitized.startIndex, offsetBy: 2)], count: 2)
            guard let int = UInt64(r + g + b, radix: 16) else { return .primary }
            return Color(red: Double((int >> 16) & 0xFF) / 255,
                         green: Double((int >> 8) & 0xFF) / 255,
                         blue: Double(int & 0xFF) / 255)
        }
        guard hexSanitized.count == 6, let int = UInt64(hexSanitized, radix: 16) else { return .primary }
        return Color(red: Double((int >> 16) & 0xFF) / 255,
                     green: Double((int >> 8) & 0xFF) / 255,
                     blue: Double(int & 0xFF) / 255)
    }
}
