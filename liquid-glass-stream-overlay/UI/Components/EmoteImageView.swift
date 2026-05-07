import SwiftUI

// MARK: - Отображение эмоутов (анимированные и статичные)
struct EmoteImageView: View {
    let url: URL
    let size: CGFloat
    let animated: Bool

    var body: some View {
        Group {
            let ext = url.pathExtension.lowercased()
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView().frame(width: 30, height: 30)
                    case .success(let image):
                        image.resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: size, height: size)
                    case .failure:
                        Text(":)").frame(width: size, height: size)
                    @unknown default:
                        EmptyView()
                    }
                }
        }
    }
}
