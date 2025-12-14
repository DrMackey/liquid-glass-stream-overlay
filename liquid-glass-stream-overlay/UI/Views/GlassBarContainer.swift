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
                            GlassBarLabel(chat: chat, isNotifictaion: false)
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

            VStack(spacing: 8) {
                HStack { Spacer(minLength: 0)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 125, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .symbolRenderingMode(.hierarchical)
                        .opacity(0.25)
                    Spacer(minLength: 0) }
                
                Text("РАЗБЛОКИРУЙТЕ ВЕБКАМЕРУ\nЗА БАЛЛЫ КАНАЛА")
                    .font(.system(size: 24, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(0.25)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
    }
}
