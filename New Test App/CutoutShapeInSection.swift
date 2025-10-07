// CutoutShapeInSection.swift
// Вспомогательная Shape для сценариев с вырезом в секции

import SwiftUI

struct CutoutShapeInSection: Shape {
    let cutoutRect: CGRect
    let cutoutCorner: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addPath(Path(rect))
        let inner = RoundedRectangle(cornerRadius: cutoutCorner, style: .continuous).path(in: cutoutRect)
        path.addPath(inner)
        return path
    }
}
