import SwiftUI

struct RAMCard: View {
    @ObservedObject var ram: RAMMonitor
    @ObservedObject var processes: ProcessMonitor
    @EnvironmentObject var settings: AppSettings
    var timeRange: HistoryTimeRange = .fiveMin
    var onExpand: (() -> Void)? = nil
    private var cfg: CardConfig { settings.config(for: .ram) }
    private var baseAccent: Color {
        guard let h = settings.config(for: .ram).accentHex,
              let rgb = UInt64(h.hasPrefix("#") ? String(h.dropFirst()) : h, radix: 16)
        else { return .purple }
        return Color(red: Double((rgb >> 16) & 0xFF) / 255,
                     green: Double((rgb >> 8) & 0xFF) / 255,
                     blue: Double(rgb & 0xFF) / 255)
    }
    private var accent: Color {
        settings.thresholdColor(value: ram.percent, threshold: settings.ramAlertThreshold, accent: baseAccent)
    }

    var body: some View {
        HoverCard {
            GlassCard {
                switch cfg.layoutMode {
                case .ring:    ringLayout
                case .compact: compactLayout
                default:       standardLayout
                }
            }
        } detail: {
            RAMDetailPanelView(ram: ram, processes: processes, accent: accent)
        }
    }

    private var standardLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Label("Memory", systemImage: "memorychip")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        if let onExpand { CardExpandButton(action: onExpand) }
                        if ram.pressureLevel > 0 { PressureBadge(level: ram.pressureLevel) }
                    }
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(String(format: "%.1f", ram.usedGB))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(accent)
                            .contentTransition(.numericText())
                        Text(String(format: "/ %.0f GB", ram.totalGB))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                RingGauge(value: ram.percent, color: accent)
                    .frame(width: 44, height: 44)
            }

            if cfg.shows("legend") && ram.totalGB > 0 {
                MemoryBreakdownBar(ram: ram).frame(height: 6)
            }

            if cfg.shows("sparkline") {
                SparklineView(values: ram.historyValues(for: timeRange), color: accent)
                    .frame(height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if cfg.shows("legend") {
                VStack(spacing: 4) {
                    MemoryLegend(ram: ram)
                    if cfg.shows("swap") && ram.swapTotalGB > 0 {
                        SwapRow(used: ram.swapUsedGB, total: ram.swapTotalGB)
                    }
                }
            }
        }
    }

    private var compactLayout: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Label("Memory", systemImage: "memorychip")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(String(format: "%.1f", ram.usedGB))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(accent)
                    Text(String(format: "/%.0fG", ram.totalGB))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            RingGauge(value: ram.percent, color: accent).frame(width: 34, height: 34)
            if let onExpand { CardExpandButton(action: onExpand) }
        }
    }

    private var ringLayout: some View {
        VStack(spacing: 8) {
            HStack {
                Label("Memory", systemImage: "memorychip")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if let onExpand { CardExpandButton(action: onExpand) }
            }
            ZStack {
                RingGauge(value: ram.percent, color: accent, label: "").frame(width: 90, height: 90)
                VStack(spacing: 0) {
                    Text(String(format: "%.1f", ram.usedGB))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(accent)
                    Text("GB")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            Text(String(format: "%.0f GB total", ram.totalGB))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private func formatMB(_ mb: Double) -> String {
        mb >= 1024 ? String(format: "%.1f GB", mb / 1024) : String(format: "%.0f MB", mb)
    }
}

// MARK: - Live-updating panel view

/// Holds @ObservedObject references so the side panel rerenders when monitors publish.
struct RAMDetailPanelView: View {
    @ObservedObject var ram: RAMMonitor
    @ObservedObject var processes: ProcessMonitor
    let accent: Color

    private var settings: AppSettings { AppSettings.shared }
    private var cfg: CardConfig { settings.config(for: .ram) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Memory — Top Processes", systemImage: "memorychip")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            if cfg.shows("processes") && !processes.topRAM.isEmpty {
                let procs = Array(processes.topRAM.prefix(settings.topProcessesCount))
                ProcessList(
                    processes: procs,
                    valueLabel: { formatMB($0.ramMB) },
                    maxValue: procs.first?.ramMB ?? 1,
                    barValue: { $0.ramMB },
                    color: accent
                )
            }

            if cfg.shows("legend") {
                Divider().opacity(0.4)
                MemoryLegend(ram: ram)
                if cfg.shows("swap") && ram.swapTotalGB > 0 {
                    SwapRow(used: ram.swapUsedGB, total: ram.swapTotalGB)
                }
            }
        }
    }

    private func formatMB(_ mb: Double) -> String {
        mb >= 1024 ? String(format: "%.1f GB", mb / 1024) : String(format: "%.0f MB", mb)
    }
}

// MARK: - Sub-views

private struct PressureBadge: View {
    let level: Int
    var body: some View {
        Text(level == 2 ? "Critical" : "Warning")
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background((level == 2 ? Color.red : .orange).opacity(0.15), in: Capsule())
            .foregroundStyle(level == 2 ? .red : .orange)
    }
}

private struct MemoryBreakdownBar: View {
    let ram: RAMMonitor

    var body: some View {
        Canvas { ctx, size in
            guard ram.totalGB > 0 else { return }
            let total = size.width
            var x: CGFloat = 0

            func draw(_ gb: Double, color: Color) {
                let w = CGFloat(gb / ram.totalGB) * total
                guard w > 0 else { return }
                ctx.fill(Path(roundedRect: CGRect(x: x, y: 0, width: w, height: size.height),
                              cornerRadius: 3),
                         with: .color(color))
                x += w
            }

            draw(ram.wiredGB,      color: .red)
            draw(ram.activeGB,     color: .purple)
            draw(ram.compressedGB, color: .orange)
            // free = remainder (transparent / background)
        }
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 3))
    }
}

private struct MemoryLegend: View {
    let ram: RAMMonitor

    var body: some View {
        HStack(spacing: 0) {
            LegendItem(color: .red,    label: "Wired",
                       value: String(format: "%.1f", ram.wiredGB))
            LegendItem(color: .purple, label: "App",
                       value: String(format: "%.1f", ram.activeGB))
            LegendItem(color: .orange, label: "Compr.",
                       value: String(format: "%.1f", ram.compressedGB))
            let free = max(0, ram.totalGB - ram.wiredGB - ram.activeGB - ram.compressedGB)
            LegendItem(color: .secondary, label: "Free",
                       value: String(format: "%.1f", free))
        }
    }
}

private struct SwapRow: View {
    let used: Double
    let total: Double

    var body: some View {
        HStack {
            Text("Swap")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text(String(format: "%.1f / %.0f GB", used, total))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(used > total * 0.7 ? .orange : .secondary)
        }
        .padding(.horizontal, 2)
    }
}

private struct LegendItem: View {
    let color: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("\(value) GB")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
