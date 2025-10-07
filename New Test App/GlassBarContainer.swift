// GlassBarContainer.swift
// Контейнер карточки Glass Bar и вложенных секций

import SwiftUI

struct GlassBarContainer: View {
    @ObservedObject var chat: TwitchChatManager

    var body: some View {
        GeometryReader { containerGeo in
            ZStack {
                RoundedRectangle(cornerRadius: 0)
                    .fill(Color.clear)
                    .background(Color.clear)
                    .glassEffect(.regular, in: .rect(cornerRadius: 30))
                
                VStack(spacing: 16) {
                    HStack(spacing: 16) {
                        VStack {
                            GlassUnlockPromptView()
                                .frame(maxHeight: .infinity)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        
                        Divider()
                            .frame(maxHeight: .infinity)
                        
                        VStack {
                            GlassBarLabel(chat: chat)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.clear)
                            .background(Color.clear)
                            .glassEffect(.regular, in: .rect(cornerRadius: 20))
                    }
                }
                .padding(16)
            }
            .compositingGroup()
            .shadow(radius: 10)
        }
    }
}

// Левый стеклянный блок с подсказкой "разблокируйте Вебкамеру"
struct GlassUnlockPromptView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.clear)
                .background(Color.clear)
                .glassEffect(.regular, in: .rect(cornerRadius: 20))

            Text("разблокируйте Вебкамеру")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
        }
    }
}
