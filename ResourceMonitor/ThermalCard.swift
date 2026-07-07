import SwiftUI

struct ThermalCard: View {
    @ObservedObject var thermal: ThermalMonitor
    @EnvironmentObject var settings: AppSettings
    var onExpand: (() -> Void)? = nil

    private var cfg: CardConfig { settings.config(for: .thermal) }
    private var accent: Color {
        guard let hex = settings.config(for: .thermal).accentHex,
              let rgb = UInt64(hex.hasPrefix("#") ? String(hex.dropFirst()) : hex, radix: 16)
        else { return .orange }
        return Color(red: Double((rgb >> 16) & 0xFF) / 255,
                     green: Double((rgb >> 8) & 0xFF) / 255,
                     blue: Double(rgb & 0xFF) / 255)
    }

    private var maxCPUTemp: Double? {
        thermal.sensors
            .filter { $0.label.hasPrefix("CPU") }
            .map(\.celsius)
            .max()
    }

    private var gpuTemp: Double? {
        thermal.sensors.first { $0.label.hasPrefix("GPU") }?.celsius
    }

    var body: some View {
        HoverCard {
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Temperature & Fans", systemImage: "thermometer.medium")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        if let onExpand { CardExpandButton(action: onExpand) }
                        Spacer()
                        ThermalStateBadge(state: thermal.thermalState)
                    }

                    if thermal.sensors.isEmpty {
                        Text("No sensors available")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 12) {
                            if let t = maxCPUTemp { TempStat(label: "CPU max", celsius: t) }
                            if let t = gpuTemp { TempStat(label: "GPU", celsius: t) }
                            if let t = thermal.sensors.first(where: { $0.label == "Battery" })?.celsius {
                                TempStat(label: "Battery", celsius: t)
                            }
                        }
                    }

                    if cfg.shows("power") && (thermal.cpuWatts > 0 || thermal.gpuWatts > 0) {
                        Divider().opacity(0.3)
                        HStack(spacing: 12) {
                            if thermal.cpuWatts > 0 { PowerStat(label: "CPU", watts: thermal.cpuWatts, color: accent) }
                            if thermal.gpuWatts > 0 { PowerStat(label: "GPU", watts: thermal.gpuWatts, color: .mint) }
                            if thermal.aneWatts > 0 { PowerStat(label: "ANE", watts: thermal.aneWatts, color: .indigo) }
                        }
                    }
                }
            }
        } detail: {
            ThermalDetailPanelView(thermal: thermal)
        }
    }
}

// MARK: - Live-updating panel view

struct ThermalDetailPanelView: View {
    @ObservedObject var thermal: ThermalMonitor

    private var cfg: CardConfig { AppSettings.shared.config(for: .thermal) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Sensors & Fans", systemImage: "thermometer.medium")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            if cfg.shows("sensors") && !thermal.sensors.isEmpty {
                let cpuSensors = thermal.sensors.filter { $0.label.hasPrefix("CPU") }
                let otherSensors = thermal.sensors.filter { !$0.label.hasPrefix("CPU") }
                if !cpuSensors.isEmpty { SensorGroup(title: "CPU Cores", sensors: cpuSensors) }
                if !otherSensors.isEmpty { SensorGroup(title: "Other", sensors: otherSensors) }
            }

            if cfg.shows("voltage") && !thermal.voltageSensors.isEmpty {
                Divider().opacity(0.3)
                VStack(spacing: 4) {
                    ForEach(thermal.voltageSensors) { sensor in
                        HStack {
                            Text(sensor.label).font(.system(size: 11)).foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.2f V", sensor.celsius))
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }

            if cfg.shows("fans") && !thermal.fans.isEmpty {
                Divider().opacity(0.3)
                VStack(spacing: 4) {
                    ForEach(thermal.fans) { fan in
                        FanRow(fan: fan,
                               isManual: thermal.fanManualMask & (1 << UInt8(fan.id)) != 0,
                               targetRPM: thermal.fanTargetRPMs[fan.id] ?? fan.minRPM,
                               fanControlAvailable: thermal.fanControlAvailable,
                               onSetManual: { thermal.setFanManual(fan.id, rpm: $0) },
                               onSetAuto:   { thermal.setFanAuto(fan.id) })
                    }
                }
                if thermal.fanManualMask != 0 {
                    Button("Reset fans to auto") { thermal.setAllFansAuto() }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.orange)
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            if cfg.shows("freq") && thermal.pCoreGHz > 0 {
                Divider().opacity(0.3)
                FreqStat(pGHz: thermal.pCoreGHz, eGHz: thermal.eCoreGHz)
            }
        }
    }
}

// MARK: - Sub-views

private struct PowerStat: View {
    let label: String
    let watts: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(String(format: "%.1f W", watts))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FreqStat: View {
    let pGHz: Double
    let eGHz: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Frequency")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            if eGHz > 0 {
                Text(String(format: "P %.2f / E %.2f GHz", pGHz, eGHz))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                Text(String(format: "%.2f GHz", pGHz))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ThermalStateBadge: View {
    let state: String
    private var color: Color {
        switch state {
        case "Normal":   return .green
        case "Moderate": return .orange
        default:         return .red
        }
    }
    var body: some View {
        Text(state)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

private struct TempStat: View {
    let label: String
    let celsius: Double
    @EnvironmentObject var settings: AppSettings

    private var color: Color {
        settings.thresholdColor(value: celsius, threshold: settings.tempAlertThreshold, accent: .primary)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(String(format: "%.0f°", celsius))
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SensorGroup: View {
    let title: String
    let sensors: [ThermalSensor]
    @State private var expanded = true

    var body: some View {
        VStack(spacing: 3) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack {
                    Text(title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(spacing: 3) {
                    ForEach(sensors) { sensor in
                        SensorRow(sensor: sensor)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

private struct SensorRow: View {
    let sensor: ThermalSensor
    @EnvironmentObject var settings: AppSettings

    private var tempColor: Color {
        settings.thresholdColor(value: sensor.celsius, threshold: settings.tempAlertThreshold, accent: .primary)
    }

    var body: some View {
        HStack {
            Text(sensor.label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text(String(format: "%.0f°C", sensor.celsius))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(tempColor)
                .contentTransition(.numericText())
        }
    }
}

private struct FanRow: View {
    let fan: FanInfo
    let isManual: Bool
    let targetRPM: Double
    let fanControlAvailable: Bool
    let onSetManual: (Double) -> Void
    let onSetAuto: () -> Void

    @State private var sliderValue: Double = 0
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "fan")
                    .font(.system(size: 11))
                    .foregroundStyle(isManual ? .orange : .secondary)
                Text("Fan \(fan.id + 1)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                if isManual {
                    Text("manual")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15), in: Capsule())
                        .foregroundStyle(.orange)
                }
                Spacer()
                Canvas { ctx, size in
                    let pct = min(fan.percent / 100, 1)
                    ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 2),
                             with: .color(.secondary.opacity(0.15)))
                    if pct > 0 {
                        ctx.fill(Path(roundedRect: CGRect(x: 0, y: 0,
                                                           width: size.width * pct,
                                                           height: size.height),
                                      cornerRadius: 2),
                                 with: .color(isManual ? .orange.opacity(0.8) : .blue.opacity(0.8)))
                    }
                }
                .frame(width: 50, height: 4)
                Text(fan.rpm > 0 ? String(format: "%.0f RPM", fan.rpm) : "Off")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(fan.rpm > 0 ? (isManual ? Color.orange : Color.blue) : Color.secondary)
                    .frame(width: 72, alignment: .trailing)
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 10))
                        .foregroundStyle(isManual ? .orange : .secondary)
                }
                .buttonStyle(.plain)
            }

            if expanded {
                Group {
                    if !fanControlAvailable {
                        Text("Fan control requires SIP to be disabled or a privileged helper. Read-only on this machine.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        VStack(spacing: 6) {
                            HStack {
                                Toggle("Manual", isOn: Binding(
                                    get: { isManual },
                                    set: { manual in
                                        if manual { onSetManual(sliderValue) } else { onSetAuto() }
                                    }))
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                                .font(.system(size: 11))
                                Spacer()
                                Text(String(format: "%.0f – %.0f RPM", fan.minRPM, fan.maxRPM))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            if isManual {
                                Slider(value: $sliderValue,
                                       in: fan.minRPM...max(fan.maxRPM, fan.minRPM + 1),
                                       step: 100) { _ in
                                    onSetManual(sliderValue)
                                }
                                .controlSize(.small)
                                .tint(.orange)
                                Text(String(format: "Target: %.0f RPM", sliderValue))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .onAppear { sliderValue = isManual ? targetRPM : fan.minRPM }
            }
        }
    }
}
