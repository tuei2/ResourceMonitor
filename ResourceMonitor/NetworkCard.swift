import SwiftUI
import AppKit

struct NetworkCard: View {
    @ObservedObject var network: NetworkMonitor
    @ObservedObject var processes: ProcessMonitor
    @EnvironmentObject var settings: AppSettings
    var timeRange: HistoryTimeRange = .fiveMin
    var onExpand: (() -> Void)? = nil
    private var cfg: CardConfig { settings.config(for: .network) }
    private var accent: Color {
        guard let h = settings.config(for: .network).accentHex,
              let rgb = UInt64(h.hasPrefix("#") ? String(h.dropFirst()) : h, radix: 16)
        else { return .cyan }
        return Color(red: Double((rgb >> 16) & 0xFF) / 255,
                     green: Double((rgb >> 8) & 0xFF) / 255,
                     blue: Double(rgb & 0xFF) / 255)
    }

    var maxScale: Double {
        let dl = network.downloadValues(for: timeRange)
        let ul = network.uploadValues(for: timeRange)
        return max(dl.max() ?? 1, ul.max() ?? 1, 0.1)
    }

    var body: some View {
        HoverCard {
            networkSummary
        } detail: {
            NetworkDetailPanelView(network: network, processes: processes, accent: accent)
        }
    }

    private var networkSummary: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                // Header
                HStack(alignment: .top) {
                    Label("Network", systemImage: "network")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                    if let onExpand { CardExpandButton(action: onExpand) }
                    if network.vpnActive {
                        VPNBadge()
                    }
                    Spacer(minLength: 6)
                    VStack(alignment: .trailing, spacing: 2) {
                        if !network.activeInterface.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: network.connectionType.systemImage)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                Text(network.activeInterface)
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if cfg.shows("localip") && !network.localIP.isEmpty {
                            CopyableIPRow(label: "Local", ip: network.localIP)
                        }
                        if cfg.shows("externalip") && !network.externalIP.isEmpty {
                            CopyableIPRow(label: "Ext", ip: network.externalIP)
                        }
                    }
                    .layoutPriority(1)
                }

                // Live speeds
                HStack(spacing: 12) {
                    SpeedBadge(direction: "down", icon: "arrow.down.circle.fill",
                               value: network.downloadMBps, color: .cyan)
                    SpeedBadge(direction: "up", icon: "arrow.up.circle.fill",
                               value: network.uploadMBps, color: .indigo)
                }

                // Sparkline (no hover interaction — details are in the side panel)
                if cfg.shows("sparkline") {
                    ZStack {
                        SparklineView(values: network.downloadValues(for: timeRange), color: accent,
                                      maxValue: maxScale)
                        SparklineView(values: network.uploadValues(for: timeRange), color: .indigo.opacity(0.7),
                                      maxValue: maxScale)
                    }
                    .frame(height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Divider().opacity(0.3)

                if cfg.shows("wifi") {
                    if !network.wifiSSID.isEmpty {
                        WiFiInfoRow(network: network)
                    } else if network.connectionType == .wifi {
                        WiFiLocationHint()
                    }
                }

                if cfg.shows("usage") {
                    HStack {
                        UsagePeriod(label: "Today", dl: network.todayDownloadGB, ul: network.todayUploadGB)
                        Divider().frame(height: 30)
                        UsagePeriod(label: "7 days", dl: network.sevenDayDownloadGB, ul: network.sevenDayUploadGB)
                        Divider().frame(height: 30)
                        UsagePeriod(label: "30 days", dl: network.thirtyDayDownloadGB, ul: network.thirtyDayUploadGB)
                    }
                }
            }
        }
    }

}

// MARK: - Live-updating panel view

struct NetworkDetailPanelView: View {
    @ObservedObject var network: NetworkMonitor
    @ObservedObject var processes: ProcessMonitor
    let accent: Color

    private var settings: AppSettings { AppSettings.shared }
    private var cfg: CardConfig { settings.config(for: .network) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Label("Network — Processes", systemImage: network.connectionType.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                if network.vpnActive { VPNBadge() }
            }

            // Butterfly chart: download below the axis, upload above.
            let dl = network.downloadValues(for: .fiveMin)
            let ul = network.uploadValues(for: .fiveMin)
            let peak = max(dl.max() ?? 0, ul.max() ?? 0, 0.1)
            ButterflyChart(download: dl, upload: ul, maxValue: peak)
                .frame(height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            let dlProcs = Array(processes.topNetDL.filter { $0.netDLMBps > 0 }
                .prefix(settings.topProcessesCount))
            let ulProcs = Array(processes.topNetUL.filter { $0.netULMBps > 0 }
                .prefix(settings.topProcessesCount))

            if !dlProcs.isEmpty {
                NetProcSection(
                    title: "Download",
                    icon: "arrow.down.circle.fill",
                    processes: dlProcs,
                    value: { formatMBps($0.netDLMBps) },
                    barValue: { $0.netDLMBps },
                    maxValue: dlProcs.first?.netDLMBps ?? 1,
                    color: .cyan
                )
            }

            if !ulProcs.isEmpty {
                if !dlProcs.isEmpty { Divider().opacity(0.3) }
                NetProcSection(
                    title: "Upload",
                    icon: "arrow.up.circle.fill",
                    processes: ulProcs,
                    value: { formatMBps($0.netULMBps) },
                    barValue: { $0.netULMBps },
                    maxValue: ulProcs.first?.netULMBps ?? 1,
                    color: .indigo
                )
            }

            if dlProcs.isEmpty && ulProcs.isEmpty {
                Text("No active network processes")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            if cfg.shows("wifi") {
                if !network.wifiSSID.isEmpty {
                    Divider().opacity(0.4)
                    WiFiInfoRow(network: network)
                } else if network.connectionType == .wifi {
                    Divider().opacity(0.4)
                    WiFiLocationHint()
                }
            }
        }
    }

    private func formatMBps(_ v: Double) -> String {
        v >= 1 ? String(format: "%.1f MB/s", v) : String(format: "%.0f KB/s", v * 1024)
    }
}

private struct NetProcSection: View {
    let title: String
    let icon: String
    let processes: [ProcessStat]
    let value: (ProcessStat) -> String
    let barValue: (ProcessStat) -> Double
    let maxValue: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(LocalizedStringKey(title), systemImage: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)

            ProcessList(
                processes: processes,
                valueLabel: value,
                maxValue: maxValue,
                barValue: barValue,
                color: color
            )
        }
    }
}

private struct NetProcessGrid: View {
    let dlProcs: [ProcessStat]
    let ulProcs: [ProcessStat]

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if !dlProcs.isEmpty {
                NetMiniList(title: "Download", processes: dlProcs,
                            value: { formatMBps($0.netDLMBps) }, color: .cyan)
            }
            if !ulProcs.isEmpty {
                NetMiniList(title: "Upload", processes: ulProcs,
                            value: { formatMBps($0.netULMBps) }, color: .indigo)
            }
        }
    }

    private func formatMBps(_ v: Double) -> String {
        v >= 1 ? String(format: "%.1fM/s", v) : String(format: "%.0fK/s", v * 1024)
    }
}

private struct NetMiniList: View {
    let title: String
    let processes: [ProcessStat]
    let value: (ProcessStat) -> String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            ForEach(processes.prefix(5)) { p in
                HStack(spacing: 4) {
                    Text(p.name)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Text(value(p))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(color)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(color.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct VPNBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 9))
            Text("VPN active")
                .font(.system(size: 9, weight: .bold))
                .lineLimit(1)
        }
        .fixedSize()
        .foregroundStyle(.green)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(.green.opacity(0.15), in: Capsule())
    }
}

/// Mirrored up/down throughput history: download grows downward, upload upward,
/// around a shared center axis — the "butterfly" visualization.
private struct ButterflyChart: View {
    let download: [Double]
    let upload: [Double]
    let maxValue: Double

    var body: some View {
        Canvas { ctx, size in
            let mid = size.height / 2
            let n = max(download.count, upload.count)
            guard n > 1, maxValue > 0 else { return }
            let step = size.width / CGFloat(n - 1)

            func path(_ values: [Double], downward: Bool) -> Path {
                var p = Path()
                p.move(to: CGPoint(x: 0, y: mid))
                for (i, v) in values.enumerated() {
                    let x = CGFloat(i) * step
                    let frac = CGFloat(min(v / maxValue, 1))
                    let y = downward ? mid + frac * mid : mid - frac * mid
                    p.addLine(to: CGPoint(x: x, y: y))
                }
                p.addLine(to: CGPoint(x: CGFloat(values.count - 1) * step, y: mid))
                p.closeSubpath()
                return p
            }

            ctx.fill(path(download, downward: true),
                     with: .linearGradient(Gradient(colors: [.cyan.opacity(0.7), .cyan.opacity(0.1)]),
                                           startPoint: CGPoint(x: 0, y: mid),
                                           endPoint: CGPoint(x: 0, y: size.height)))
            ctx.fill(path(upload, downward: false),
                     with: .linearGradient(Gradient(colors: [.indigo.opacity(0.7), .indigo.opacity(0.1)]),
                                           startPoint: CGPoint(x: 0, y: mid),
                                           endPoint: CGPoint(x: 0, y: 0)))
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: 0, y: mid))
                p.addLine(to: CGPoint(x: size.width, y: mid))
            }, with: .color(.secondary.opacity(0.3)), lineWidth: 0.5)
        }
    }
}

private struct WiFiLocationHint: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "location.slash")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
            Text("Enable Location access to show Wi-Fi name & signal")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct WiFiInfoRow: View {
    let network: NetworkMonitor

    private var rssiColor: Color {
        switch network.wifiRSSI {
        case (-50)...: return .green
        case (-70)...(-51): return .orange
        default: return .red
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi")
                .font(.system(size: 10))
                .foregroundStyle(.cyan)
            Text(network.wifiSSID)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if network.wifiRSSI != 0 {
                Text("\(network.wifiRSSI) dBm")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(rssiColor)
            }
            if network.wifiChannel > 0 {
                Text("ch\(network.wifiChannel)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            if network.wifiTxMbps > 0 {
                Text(String(format: "%.0f Mbps", network.wifiTxMbps))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SpeedBadge: View {
    let direction: String
    let icon: String
    let value: Double
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.system(size: 16))
            VStack(alignment: .leading, spacing: 0) {
                Text(formatMBps(value))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                    .contentTransition(.numericText())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formatMBps(_ mb: Double) -> String {
        if mb >= 1000 { return String(format: "%.2f GB/s", mb / 1024) }
        if mb >= 1    { return String(format: "%.1f MB/s", mb) }
        return String(format: "%.0f KB/s", mb * 1024)
    }
}

private struct CopyableIPRow: View {
    let label: String
    let ip: String
    @State private var copied = false

    var body: some View {
        HStack(spacing: 5) {
            Text(LocalizedStringKey(label))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize()
            Text(ip)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(ip, forType: .string)
                withAnimation { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation { copied = false }
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundStyle(copied ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct UsagePeriod: View {
    let label: String
    let dl: Double
    let ul: Double

    var body: some View {
        VStack(spacing: 3) {
            Text(LocalizedStringKey(label))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.3)
            HStack(spacing: 3) {
                Image(systemName: "arrow.down").font(.system(size: 10))
                    .foregroundStyle(.cyan)
                Text(formatGB(dl))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
            }
            HStack(spacing: 3) {
                Image(systemName: "arrow.up").font(.system(size: 10))
                    .foregroundStyle(.indigo)
                Text(formatGB(ul))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func formatGB(_ gb: Double) -> String {
        gb >= 1 ? String(format: "%.1f GB", gb) : String(format: "%.0f MB", gb * 1024)
    }
}
