import SwiftUI

struct BatteryCard: View {
    @ObservedObject var battery: BatteryMonitor
    @EnvironmentObject var settings: AppSettings
    var onExpand: (() -> Void)? = nil

    private var cfg: CardConfig { settings.config(for: .battery) }

    private var accentColor: Color {
        switch battery.percent {
        case 0..<20: return .red
        case 20..<40: return .orange
        default: return battery.isCharging ? .green : .teal
        }
    }

    var body: some View {
        HoverCard {
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                Label("Battery", systemImage: batteryIcon)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                if let onExpand { CardExpandButton(action: onExpand) }
                            }
                            HStack(alignment: .lastTextBaseline, spacing: 6) {
                                Text("\(battery.percent)%")
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundStyle(accentColor)
                                    .contentTransition(.numericText())
                                if battery.isCharging {
                                    Image(systemName: "bolt.fill")
                                        .foregroundStyle(.green)
                                        .font(.system(size: 14, weight: .bold))
                                }
                            }
                        }
                        Spacer()
                        RingGauge(value: Double(battery.percent), color: accentColor)
                            .frame(width: 44, height: 44)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4).fill(accentColor.opacity(0.12))
                            RoundedRectangle(cornerRadius: 4).fill(accentColor)
                                .frame(width: geo.size.width * CGFloat(battery.percent) / 100)
                                .animation(.easeInOut(duration: 0.4), value: battery.percent)
                        }
                    }
                    .frame(height: 6)
                }
            }
        } detail: {
            BatteryDetailPanelView(battery: battery,
                                   processes: AppState.shared.processes)
        }
    }

    private var batteryIcon: String { BatteryDetailPanelView.batteryIcon(for: battery) }
    private var healthColor: Color  { BatteryDetailPanelView.healthColor(for: battery) }
}

// MARK: - Live-updating panel view

struct BatteryDetailPanelView: View {
    @ObservedObject var battery: BatteryMonitor
    @ObservedObject var processes: ProcessMonitor

    private var cfg: CardConfig { AppSettings.shared.config(for: .battery) }
    private var settings: AppSettings { AppSettings.shared }

    // powerWatts = battery amperage × voltage (positive = charging into battery, negative = draining)
    // adapterWatts = total adapter output (may be 0 if adapter doesn't report)
    //
    // batteryW: power flowing INTO the battery (only when charging)
    // systemW:  power consumed by the system
    //   - plugged in + charging: adapter supplies both battery and system → systemW = adapter - battery
    //   - plugged in + full (not charging): all adapter goes to system → systemW = adapterWatts (or |powerWatts| as proxy)
    //   - on battery: system draws from battery → systemW = |powerWatts|
    private var batteryW: Double {
        battery.isCharging ? max(0, battery.powerWatts) : 0
    }
    private var systemW: Double {
        if battery.isPluggedIn {
            let adapterW = Double(battery.adapterWatts)
            if battery.isCharging && adapterW > 0 {
                return max(0, adapterW - batteryW)
            }
            // Full or not charging: use |powerWatts| as system draw proxy
            // (battery reports small maintenance current; abs gives actual system load)
            return max(0, abs(battery.powerWatts))
        }
        return abs(battery.powerWatts)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Battery", systemImage: Self.batteryIcon(for: battery))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            // ── Power flow diagram ──────────────────────────────────────────
            PowerFlowDiagram(
                sourceLabel:  battery.isPluggedIn
                    ? (battery.chargerName.isEmpty ? "Adapter" : battery.chargerName)
                    : "Battery",
                sourceIcon:   battery.isPluggedIn ? "bolt.fill" : "battery.75percent",
                sourceWatts:  battery.isPluggedIn ? Double(battery.adapterWatts) : abs(battery.powerWatts),
                batteryWatts: batteryW,
                systemWatts:  systemW,
                isCharging:   battery.isCharging,
                isPluggedIn:  battery.isPluggedIn
            )

            // ── Capacity ────────────────────────────────────────────────────
            if battery.designCapacityMAh > 0 {
                Divider().opacity(0.3)
                CapacityRow(current: battery.maxCapacityMAh,
                            design:  battery.designCapacityMAh)
            }

            // ── Info rows ───────────────────────────────────────────────────
            Divider().opacity(0.3)
            infoRows

            // ── Top energy consumers ────────────────────────────────────────
            let energyProcs = Array(processes.topEnergy
                .prefix(settings.topProcessesCount))
            if !energyProcs.isEmpty {
                Divider().opacity(0.3)
                VStack(alignment: .leading, spacing: 6) {
                    Label("Energy Impact", systemImage: "bolt.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                    ProcessList(
                        processes: energyProcs,
                        valueLabel: { String(format: "%.0f", $0.energyImpact) },
                        maxValue: energyProcs.first?.energyImpact ?? 1,
                        barValue: { $0.energyImpact },
                        color: .orange
                    )
                }
            }
        }
    }

    private var infoRows: some View {
        VStack(spacing: 6) {
            if cfg.shows("health") && battery.macOSHealthPercent > 0 {
                BatteryRow(icon: "apple.logo", label: "macOS Health",
                           value: "\(battery.macOSHealthPercent)%",
                           valueColor: Self.healthColor(pct: battery.macOSHealthPercent))
            }
            if cfg.shows("cycles") && battery.cycleCount > 0 {
                Divider().opacity(0.3)
                BatteryRow(icon: "arrow.clockwise", label: "Cycles",
                           value: "\(battery.cycleCount)", valueColor: .secondary)
            }
            if cfg.shows("time"), let timeStr = timeRemainingString {
                Divider().opacity(0.3)
                BatteryRow(icon: battery.isCharging ? "clock.arrow.circlepath" : "clock",
                           label: battery.isCharging ? "Until full" : "Until empty",
                           value: timeStr, valueColor: .secondary)
            }
        }
    }

    private var timeRemainingString: String? {
        let minutes = battery.isCharging ? battery.timeToFullMin : battery.timeToEmptyMin
        guard minutes > 0 else { return nil }
        let h = minutes / 60; let m = minutes % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    static func batteryIcon(for battery: BatteryMonitor) -> String {
        if battery.isCharging { return "battery.100percent.bolt" }
        switch battery.percent {
        case 0..<10:  return "battery.0percent"
        case 10..<40: return "battery.25percent"
        case 40..<65: return "battery.50percent"
        case 65..<90: return "battery.75percent"
        default:      return "battery.100percent"
        }
    }

    static func healthColor(for battery: BatteryMonitor) -> Color {
        healthColor(pct: battery.health)
    }

    static func healthColor(pct: Int) -> Color {
        switch pct {
        case 85...: return .green
        case 70..<85: return .orange
        default: return .red
        }
    }
}

// MARK: - Power flow diagram

private struct PowerFlowDiagram: View {
    let sourceLabel:  String
    let sourceIcon:   String
    let sourceWatts:  Double
    let batteryWatts: Double
    let systemWatts:  Double
    let isCharging:   Bool
    let isPluggedIn:  Bool

    private var total: Double { max(sourceWatts, 0.1) }
    private var batteryRatio: CGFloat { CGFloat(batteryWatts / total) }
    private var systemRatio:  CGFloat { CGFloat(systemWatts  / total) }

    var body: some View {
        ZStack {
            // Bezier flow lines drawn on Canvas
            Canvas { ctx, size in
                let srcX:     CGFloat = 56
                let srcY:     CGFloat = size.height / 2
                let dstX:     CGFloat = size.width - 72
                let topY:     CGFloat = size.height * 0.25
                let botY:     CGFloat = size.height * 0.75
                let maxThick: CGFloat = 14

                func flowPath(endY: CGFloat) -> Path {
                    var p = Path()
                    p.move(to: CGPoint(x: srcX, y: srcY))
                    let cx = (srcX + dstX) / 2
                    p.addCurve(to: CGPoint(x: dstX, y: endY),
                               control1: CGPoint(x: cx, y: srcY),
                               control2: CGPoint(x: cx, y: endY))
                    return p
                }

                if isPluggedIn && isCharging && batteryWatts > 0 {
                    // Two flows: battery (green) + system (blue)
                    ctx.stroke(flowPath(endY: topY),
                               with: .color(Color.green.opacity(0.55)),
                               style: StrokeStyle(lineWidth: max(2, batteryRatio * maxThick),
                                                  lineCap: .round))
                    ctx.stroke(flowPath(endY: botY),
                               with: .color(Color.blue.opacity(0.55)),
                               style: StrokeStyle(lineWidth: max(2, systemRatio * maxThick),
                                                  lineCap: .round))
                } else {
                    // Single flow: everything to system
                    ctx.stroke(flowPath(endY: botY),
                               with: .color(Color.orange.opacity(0.55)),
                               style: StrokeStyle(lineWidth: maxThick * 0.6, lineCap: .round))
                }
            }

            // Source label (left)
            VStack(spacing: 2) {
                Image(systemName: sourceIcon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isPluggedIn ? .yellow : .teal)
                if sourceWatts > 0 {
                    Text(String(format: "%.0fW", sourceWatts))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)

            // Destination labels (right)
            VStack(spacing: 0) {
                if isPluggedIn && isCharging && batteryWatts > 0 {
                    FlowDestination(icon: "battery.100percent.bolt",
                                    watts: batteryWatts, color: .green)
                    Spacer()
                }
                FlowDestination(icon: "laptopcomputer",
                                watts: systemWatts, color: .blue)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 4)
        }
        .frame(height: isPluggedIn && isCharging && batteryWatts > 0 ? 72 : 44)
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct FlowDestination: View {
    let icon: String
    let watts: Double
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(String(format: "%.2f W", watts))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(color)
        }
    }
}

// MARK: - Capacity row

private struct CapacityRow: View {
    let current: Int  // mAh after wear
    let design:  Int  // original mAh

    private var pct: Int { design > 0 ? min(100, current * 100 / design) : 0 }
    private var barColor: Color {
        switch pct {
        case 85...: return .teal
        case 70..<85: return .orange
        default: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Capacity", systemImage: "bolt.batteryblock")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(pct)%")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(barColor)
                Text("· \(current) / \(design) mAh")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(barColor.opacity(0.12))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor.opacity(0.7))
                        .frame(width: geo.size.width * CGFloat(pct) / 100)
                }
            }
            .frame(height: 5)
        }
    }
}

struct BatteryRow: View {
    let icon: String
    let label: String
    let value: String
    let valueColor: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(valueColor)
        }
    }
}
