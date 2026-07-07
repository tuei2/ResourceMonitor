import SwiftUI
import AppKit

// Module-level hex-to-Color conversion. Used by card views and settings.
func hexColor(_ hex: String) -> Color {
    let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    let rgb = UInt64(h, radix: 16) ?? 0
    return Color(red:   Double((rgb >> 16) & 0xFF) / 255,
                 green: Double((rgb >>  8) & 0xFF) / 255,
                 blue:  Double( rgb        & 0xFF) / 255)
}

func hexString(from color: Color) -> String {
    let c = NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor(color)
    let r = Int((c.redComponent   * 255).rounded())
    let g = Int((c.greenComponent * 255).rounded())
    let b = Int((c.blueComponent  * 255).rounded())
    return String(format: "%02X%02X%02X", r, g, b)
}
