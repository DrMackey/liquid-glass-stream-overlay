import Foundation
import Combine


// MARK: - Автоочистка уведомлений
func setupNotificationsAutoClear(
    notificationDisplayTime: TimeInterval,
    manager: TwitchChatManager,
    cancellables: inout Set<AnyCancellable>  // ⚠️ inout для изменения
) {
    var lastKnown: [Notification] = []
    
    manager.$notifications  // ✅ $ вместо просто notifications
        .receive(on: DispatchQueue.main)
        .sink { current in
            let lastIds = Set(lastKnown.map { $0.id })
            let newOnes = current.filter { !lastIds.contains($0.id) }
            
            for notif in newOnes {
                DispatchQueue.main.asyncAfter(deadline: .now() + notificationDisplayTime) {
                    manager.notifications.removeAll { $0.id == notif.id }  // ✅ напрямую к manager
                }
            }
            lastKnown = current
        }
        .store(in: &cancellables)  // ⚠️ & для inout
}
