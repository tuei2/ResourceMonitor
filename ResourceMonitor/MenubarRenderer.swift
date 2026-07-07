import AppKit
import CoreGraphics

private extension NSColor {
    convenience init?(hex: String) {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard h.count == 6, let rgb = UInt64(h, radix: 16) else { return nil }
        self.init(red:   CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >>  8) & 0xFF) / 255,
                  blue:  CGFloat( rgb        & 0xFF) / 255,
                  alpha: 1)
    }
}

enum MenubarRenderer {

    static func render(state: AppState, settings: AppSettings) -> NSAttributedString {
        let items = settings.menubarItems.filter { $0.enabled }
        guard !items.isEmpty else { return plain("◉") }

        let result = NSMutableAttributedString()
        for (idx, item) in items.enumerated() {
            if idx > 0 { result.append(plain("  ")) }
            result.append(segment(item: item, state: state))
        }
        return result
    }

    // MARK: - Per-metric segment

    private static func segment(item: MenubarItemConfig, state: AppState) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let color = resolvedTint(item: item, state: state)

        for (i, element) in item.elements.enumerated() {
            if i > 0 { result.append(plain(" ", color: color)) }
            switch element {
            case .icon:
                result.append(sfSymbol(item.metric, state: state, size: 11, color: color))
            case .label:
                let text = item.customLabel.isEmpty ? item.metric.label : item.customLabel
                result.append(plain(text, color: color))
            case .ring:
                let fraction = ringFraction(item.metric, state: state)
                let ringColor = color ?? .labelColor
                if let img = drawRing(fraction: fraction, color: ringColor,
                                      size: NSSize(width: 14, height: 14)) {
                    result.append(imageAttachment(img, baselineOffset: -2))
                }
            case .sparkline:
                let hist = history(item.metric, state: state)
                let lineColor = color ?? .labelColor
                if !hist.isEmpty,
                   let img = drawSparkline(hist, color: lineColor, size: NSSize(width: 32, height: 14)) {
                    result.append(imageAttachment(img, baselineOffset: -2))
                }
            case .value:
                result.append(plain(value(item.metric, state: state), color: color))
            case .pressure:
                if item.metric == .ram {
                    result.append(pressureDot(level: state.ram.pressureLevel))
                }
            }
        }
        return result
    }

    // MARK: - Color resolution

    /// Base tint from appearance-aware custom color (nil = use labelColor).
    private static func baseTint(item: MenubarItemConfig) -> NSColor? {
        let isDark = NSApp.effectiveAppearance
            .bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let hex = isDark ? item.darkTintHex : item.lightTintHex
        return hex.flatMap { NSColor(hex: $0) }
    }

    /// Final tint: threshold colors override the custom color when breached.
    private static func resolvedTint(item: MenubarItemConfig, state: AppState) -> NSColor? {
        // Threshold override takes priority
        if let t = thresholdTint(item.metric, state: state) { return t }
        return baseTint(item: item)
    }

    private static func thresholdTint(_ metric: MenubarMetric, state: AppState) -> NSColor? {
        switch metric {
        case .cpu:
            let u = state.cpu.usage
            let warn = AppSettings.shared.cpuAlertThreshold
            return u >= min(warn + 15, 99) ? .systemRed : u >= warn ? .systemOrange : nil
        case .ram:
            switch state.ram.pressureLevel {
            case 2: return .systemRed
            case 1: return .systemOrange
            default: return nil
            }
        case .battery:
            if state.battery.percent < 20 { return .systemRed }
            if state.battery.percent < 40 { return .systemOrange }
            return state.battery.isCharging ? .systemGreen : nil
        case .network:
            return nil
        case .temperature:
            let max = state.thermal.sensors
                .filter { $0.label.hasPrefix("CPU ") }.map(\.celsius).max() ?? 0
            let warn = AppSettings.shared.tempAlertThreshold
            return max >= min(warn + 15, 150) ? .systemRed : max >= warn ? .systemOrange : nil
        }
    }

    // MARK: - Value strings

    private static func value(_ metric: MenubarMetric, state: AppState) -> String {
        switch metric {
        case .cpu:         return String(format: "%.0f%%", state.cpu.usage)
        case .ram:         return String(format: "%.1fG", state.ram.usedGB)
        case .battery:
            let icon = state.battery.isCharging ? "⚡" : ""
            return "\(icon)\(state.battery.percent)%"
        case .network:
            return "↓\(formatMBps(state.network.downloadMBps)) ↑\(formatMBps(state.network.uploadMBps))"
        case .temperature:
            let max = state.thermal.sensors
                .filter { $0.label.hasPrefix("CPU ") }.map(\.celsius).max()
            return max.map { String(format: "%.0f°", $0) } ?? "—°"
        }
    }

    private static func pressureDot(level: Int) -> NSAttributedString {
        let color: NSColor = level == 2 ? .systemRed : level == 1 ? .systemOrange : .systemGreen
        return plain("●", color: color)
    }

    private static func formatMBps(_ mbps: Double) -> String {
        if mbps >= 100 { return String(format: "%.0fM", mbps) }
        if mbps >= 1   { return String(format: "%.1fM", mbps) }
        return String(format: "%.0fK", mbps * 1024)
    }

    // MARK: - Ring fraction

    private static func ringFraction(_ metric: MenubarMetric, state: AppState) -> Double {
        switch metric {
        case .cpu:         return state.cpu.usage / 100
        case .ram:         return state.ram.totalGB > 0 ? state.ram.usedGB / state.ram.totalGB : 0
        case .battery:     return Double(state.battery.percent) / 100
        case .network:     return 0
        case .temperature:
            let max = state.thermal.sensors.filter { $0.label.hasPrefix("CPU ") }.map(\.celsius).max() ?? 0
            return min(max / 100, 1)
        }
    }

    // MARK: - History

    private static func history(_ metric: MenubarMetric, state: AppState) -> [Double] {
        switch metric {
        case .cpu:         return Array(state.cpu.history.suffix(30))
        case .ram:         return Array(state.ram.history.suffix(30))
        case .battery:     return []
        case .network:     return Array(state.network.downloadHistory.suffix(30))
        case .temperature: return []
        }
    }

    // MARK: - SF Symbol with tint

    private static func sfSymbol(_ metric: MenubarMetric, state: AppState,
                                  size: CGFloat, color: NSColor?) -> NSAttributedString {
        let name: String
        switch metric {
        case .cpu:         name = "cpu"
        case .ram:         name = "memorychip"
        case .battery:     name = state.battery.isCharging ? "battery.100percent.bolt" : "battery.75percent"
        case .network:
            // Reflect the active connection type; a shield with a lock when on VPN.
            // Use the non-filled variant: the .fill version renders as a solid
            // shield with no visible lock in the monochrome menu bar.
            if state.network.vpnActive {
                name = "lock.shield"
            } else {
                switch state.network.connectionType {
                case .wifi:     name = "wifi"
                case .ethernet: name = "cable.connector"
                case .other:    name = "network"
                }
            }
        case .temperature: name = "thermometer.medium"
        }
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
            return NSAttributedString()
        }
        var config = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
        if let c = color ?? NSColor.labelColor as NSColor? {
            config = config.applying(NSImage.SymbolConfiguration(paletteColors: [c]))
        }
        let img = base.withSymbolConfiguration(config) ?? base
        return imageAttachment(img, baselineOffset: -2)
    }

    // MARK: - Ring drawing

    private static func drawRing(fraction: Double, color: NSColor, size: NSSize) -> NSImage? {
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return nil }

        let cx = size.width / 2, cy = size.height / 2
        let r = min(cx, cy) - 1
        let lineW: CGFloat = 2.5
        let start = CGFloat.pi / 2

        ctx.setLineWidth(lineW)
        ctx.setStrokeColor(color.withAlphaComponent(0.2).cgColor)
        ctx.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                   startAngle: 0, endAngle: 2 * .pi, clockwise: false)
        ctx.strokePath()

        if fraction > 0.01 {
            ctx.setStrokeColor(color.withAlphaComponent(0.9).cgColor)
            ctx.setLineCap(.round)
            ctx.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                       startAngle: start, endAngle: start - CGFloat(fraction * 2 * .pi),
                       clockwise: true)
            ctx.strokePath()
        }
        return image
    }

    // MARK: - Sparkline drawing

    private static func drawSparkline(_ values: [Double], color: NSColor, size: NSSize) -> NSImage? {
        guard !values.isEmpty else { return nil }
        let maxVal = max(values.max() ?? 1, 1)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return nil }

        let w = size.width, h = size.height
        let step = values.count > 1 ? w / CGFloat(values.count - 1) : w

        let fill = CGMutablePath()
        fill.move(to: CGPoint(x: 0, y: 0))
        for (i, v) in values.enumerated() {
            fill.addLine(to: CGPoint(x: CGFloat(i) * step, y: CGFloat(v / maxVal) * (h - 2) + 1))
        }
        fill.addLine(to: CGPoint(x: w, y: 0))
        fill.closeSubpath()
        ctx.addPath(fill)
        ctx.setFillColor(color.withAlphaComponent(0.18).cgColor)
        ctx.fillPath()

        let line = CGMutablePath()
        for (i, v) in values.enumerated() {
            let pt = CGPoint(x: CGFloat(i) * step, y: CGFloat(v / maxVal) * (h - 2) + 1)
            if i == 0 { line.move(to: pt) } else { line.addLine(to: pt) }
        }
        ctx.addPath(line)
        ctx.setStrokeColor(color.withAlphaComponent(0.9).cgColor)
        ctx.setLineWidth(1.2)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.strokePath()

        if let last = values.last {
            let y = CGFloat(last / maxVal) * (h - 2) + 1
            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: CGRect(x: w - 2, y: y - 2, width: 4, height: 4))
        }
        return image
    }

    // MARK: - Helpers

    private static func plain(_ string: String, color: NSColor? = nil) -> NSAttributedString {
        var attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        ]
        if let c = color { attrs[.foregroundColor] = c }
        return NSAttributedString(string: string, attributes: attrs)
    }

    private static func imageAttachment(_ image: NSImage, baselineOffset: CGFloat) -> NSAttributedString {
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = CGRect(x: 0, y: baselineOffset,
                                   width: image.size.width, height: image.size.height)
        return NSAttributedString(attachment: attachment)
    }
}
