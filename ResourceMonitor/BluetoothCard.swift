import SwiftUI

struct BluetoothCard: View {
    @ObservedObject var bluetooth: BluetoothMonitor
    @EnvironmentObject var settings: AppSettings

    private var visibleDevices: [BluetoothDevice] {
        settings.bluetoothShowOnlyConnected
            ? bluetooth.devices.filter { $0.isConnected }
            : bluetooth.devices
    }

    var body: some View {
        HoverCard {
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Bluetooth", systemImage: "dot.radiowaves.left.and.right")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Toggle(isOn: $settings.bluetoothShowOnlyConnected) {
                            Text("Connected only")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .toggleStyle(.checkbox)
                    }

                    if !visibleDevices.isEmpty {
                        VStack(spacing: 6) {
                            ForEach(visibleDevices.prefix(3)) { device in
                                BTDeviceRow(device: device)
                            }
                            if visibleDevices.count > 3 {
                                Text("+ \(visibleDevices.count - 3) more — hover for all")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else if bluetooth.permission == .denied || bluetooth.permission == .unsupported {
                        BluetoothPermissionNotice(permission: bluetooth.permission) {
                            bluetooth.openPrivacySettings()
                        }
                    } else {
                        Text(settings.bluetoothShowOnlyConnected ? "No connected devices" : "No paired devices")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } detail: {
            BluetoothDetailPanelView(bluetooth: bluetooth)
        }
        .onAppear { bluetooth.refreshOnce() }
    }
}

// MARK: - Live-updating panel view

struct BluetoothDetailPanelView: View {
    @ObservedObject var bluetooth: BluetoothMonitor

    private var settings: AppSettings { AppSettings.shared }

    private var visibleDevices: [BluetoothDevice] {
        settings.bluetoothShowOnlyConnected
            ? bluetooth.devices.filter { $0.isConnected }
            : bluetooth.devices
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("All Bluetooth Devices", systemImage: "dot.radiowaves.left.and.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            if !visibleDevices.isEmpty {
                VStack(spacing: 6) {
                    ForEach(visibleDevices) { device in
                        BTDeviceRow(device: device)
                    }
                }
            } else if bluetooth.permission == .denied || bluetooth.permission == .unsupported {
                BluetoothPermissionNotice(permission: bluetooth.permission) {
                    bluetooth.openPrivacySettings()
                }
            } else {
                Text(settings.bluetoothShowOnlyConnected ? "No connected devices" : "No paired devices")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Permission notice

private struct BluetoothPermissionNotice: View {
    let permission: BluetoothPermission
    let onGrant: () -> Void

    private var message: String {
        switch permission {
        case .denied:      return "Bluetooth access is denied. Enable it to see your devices."
        case .unsupported: return "Bluetooth is unavailable on this Mac."
        case .unknown:     return "Requesting Bluetooth access…"
        case .authorized:  return ""
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "lock.slash")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                Text(LocalizedStringKey(message))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if permission == .denied {
                Button("Open Bluetooth settings", action: onGrant)
                    .font(.system(size: 11))
                    .buttonStyle(.link)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BTDeviceRow: View {
    let device: BluetoothDevice

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: device.category.systemImage)
                .font(.system(size: 14))
                .foregroundStyle(device.isConnected ? .blue : .secondary)
                .frame(width: 20)

            Text(device.name)
                .font(.system(size: 12))
                .foregroundStyle(device.isConnected ? .primary : .secondary)
                .lineLimit(1)

            Spacer()

            if device.batteryPercent >= 0 {
                HStack(spacing: 3) {
                    Image(systemName: batteryIcon(device.batteryPercent))
                        .font(.system(size: 11))
                        .foregroundStyle(batteryColor(device.batteryPercent))
                    Text("\(device.batteryPercent)%")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(batteryColor(device.batteryPercent))
                }
            } else if !device.isConnected {
                Text("Disconnected")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(device.isConnected ? 1 : 0.5)
    }

    private func batteryIcon(_ pct: Int) -> String {
        switch pct {
        case 0..<10:  return "battery.0percent"
        case 10..<40: return "battery.25percent"
        case 40..<65: return "battery.50percent"
        case 65..<90: return "battery.75percent"
        default:      return "battery.100percent"
        }
    }

    private func batteryColor(_ pct: Int) -> Color {
        switch pct {
        case 0..<20:  return .red
        case 20..<40: return .orange
        default:      return .green
        }
    }
}
