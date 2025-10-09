// AnimationUtils.swift
// Общие утилиты анимации и интерполяции, используются несколькими компонентами

import CoreGraphics

// Линейная интерполяция
@inlinable
func lerp(_ a: CGFloat, _ b: CGFloat, t: CGFloat) -> CGFloat {
    a + (b - a) * t
}

// Плавная функция easeInOut для синхронизации анимаций
@inlinable
func easeInOut(_ t: CGFloat) -> CGFloat {
    t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t
}
