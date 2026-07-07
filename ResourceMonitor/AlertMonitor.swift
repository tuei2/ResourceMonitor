import Foundation
import UserNotifications

final class AlertMonitor {
    static let shared = AlertMonitor()

    private let settings = AppSettings.shared
    private var consecutiveCounts: [AlertKind: Int] = [:]
    private var lastAlertTime:     [AlertKind: Date] = [:]

    enum AlertKind: String {
        case cpu, ram, temperature

        var title: String {
            switch self {
            case .cpu:         return "High CPU Usage"
            case .ram:         return "High Memory Usage"
            case .temperature: return "High Temperature"
            }
        }
    }

    // Called once at startup
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // Called on every monitor tick
    func check(appState: AppState) {
        guard settings.alertsEnabled else { return }

        evaluate(.cpu,         value: appState.cpu.usage,
                 threshold: settings.cpuAlertThreshold,
                 body: String(format: "CPU is at %.0f%%", appState.cpu.usage))

        evaluate(.ram,         value: appState.ram.percent,
                 threshold: settings.ramAlertThreshold,
                 body: String(format: "Memory is at %.0f%%", appState.ram.percent))

        let maxTemp = appState.thermal.sensors.map(\.celsius).max() ?? 0
        evaluate(.temperature, value: maxTemp,
                 threshold: settings.tempAlertThreshold,
                 body: String(format: "CPU temperature is %.0f°C", maxTemp))
    }

    private func evaluate(_ kind: AlertKind, value: Double, threshold: Double, body: String) {
        if value >= threshold {
            consecutiveCounts[kind, default: 0] += 1
        } else {
            consecutiveCounts[kind] = 0
            return
        }

        guard consecutiveCounts[kind, default: 0] >= settings.alertDebounceCount else { return }

        let now = Date()
        if let last = lastAlertTime[kind],
           now.timeIntervalSince(last) < settings.alertCooldownSeconds { return }

        lastAlertTime[kind] = now
        consecutiveCounts[kind] = 0
        fire(kind: kind, body: body)
    }

    private func fire(kind: AlertKind, body: String) {
        let content = UNMutableNotificationContent()
        content.title = kind.title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "\(kind.rawValue)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
