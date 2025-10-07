// GlassBarMaskShape.swift
// Анимируемая Shape-маска с вырезом, синхронизированная с overlay

import SwiftUI

struct GlassBarMaskShape: Shape {
    var progress: CGFloat

    var inset: CGFloat = 17
    var cutoutCorner: CGFloat = 20
    var outerCorner: CGFloat = 0
    var leftPanelWidth: CGFloat = 72
    var hSpacing: CGFloat = 16

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let parentPadding: CGFloat = 16
        let contentRect = rect.insetBy(dx: parentPadding, dy: parentPadding)

        let size = contentRect.size

        let lowerHeight = size.height / 2.0
        let oldYLocal = lowerHeight + inset
        let oldHeight = max(0, lowerHeight - inset * 2)
        let bottomYLocal = oldYLocal + oldHeight
        let newYLocal = max(0, oldYLocal - 8)
        let newHeight = max(0, bottomYLocal - newYLocal)

        let targetCutoutRectLocal = CGRect(
            x: leftPanelWidth + hSpacing + inset,
            y: newYLocal,
            width: max(0, size.width - (leftPanelWidth + hSpacing) - inset * 2),
            height: newHeight
        )
        let targetCutoutRect = targetCutoutRectLocal.offsetBy(dx: contentRect.minX, dy: contentRect.minY)

        let startCutoutRect = contentRect

        let t = max(0, min(1, progress))
        let easedT = easeInOut(t)
        
        let animatedCutoutRect = CGRect(
            x: lerp(startCutoutRect.minX, targetCutoutRect.minX, t: easedT),
            y: lerp(startCutoutRect.minY, targetCutoutRect.minY, t: easedT),
            width: lerp(startCutoutRect.width, targetCutoutRect.width, t: easedT),
            height: lerp(startCutoutRect.height, targetCutoutRect.height, t: easedT)
        )

        var p = Path()
        let outerPath = RoundedRectangle(cornerRadius: outerCorner, style: .continuous).path(in: rect)
        p.addPath(outerPath)
        let cutoutPath = RoundedRectangle(cornerRadius: cutoutCorner, style: .continuous).path(in: animatedCutoutRect)
        p.addPath(cutoutPath)
        return p
    }
}

private func lerp(_ a: CGFloat, _ b: CGFloat, t: CGFloat) -> CGFloat {
    return a + (b - a) * t
}

private func easeInOut(_ t: CGFloat) -> CGFloat {
    return t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t
}
