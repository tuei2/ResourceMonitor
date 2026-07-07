import Foundation
import Combine
import SwiftUI

// MARK: - Enums

enum PopoverCard: String, CaseIterable, Codable, Identifiable {
    case cpu, ram, battery, disk, network, gpu, thermal, bluetooth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu:       return L("CPU")
        case .ram:       return L("Memory")
        case .battery:   return L("Battery")
        case .disk:      return L("Disk")
        case .network:   return L("Network")
        case .gpu:       return L("GPU")
        case .thermal:   return L("Temperature & Fans")
        case .bluetooth: return L("Bluetooth")
        }
    }

    var systemImage: String {
        switch self {
        case .cpu:       return "cpu"
        case .ram:       return "memorychip"
        case .battery:   return "battery.100percent"
        case .disk:      return "internaldrive"
        case .network:   return "network"
        case .gpu:       return "display"
        case .thermal:   return "thermometer.medium"
        case .bluetooth: return "dot.radiowaves.left.and.right"
        }
    }

    // Available element keys per card type for per-card visibility toggles
    var availableElements: [(key: String, label: String)] {
        switch self {
        case .cpu:
            return [("sparkline",L("History graph")), ("percore",L("Per-core bars")),
                    ("clusters",L("P/E-core clusters")), ("userload",L("User/System/Idle")),
                    ("loadavg",L("Load averages")), ("processes",L("Process list"))]
        case .ram:
            return [("sparkline",L("History graph")), ("legend",L("Memory legend")),
                    ("swap",L("Swap usage")), ("processes",L("Process list"))]
        case .network:
            return [("sparkline",L("Activity graph")), ("wifi",L("Wi-Fi details")),
                    ("usage",L("Daily usage")), ("processes",L("Process list")),
                    ("localip",L("Local IP")), ("externalip",L("External IP"))]
        case .disk:
            return [("volumes",L("Disk volumes")), ("sparkline",L("IO graph")),
                    ("processes",L("Process list"))]
        case .thermal:
            return [("sensors",L("Sensor list")), ("fans",L("Fan speeds")),
                    ("power",L("Power draw")), ("freq",L("CPU frequency")),
                    ("voltage",L("Voltage sensors"))]
        case .battery:
            return [("health",L("Battery health")), ("cycles",L("Cycle count")),
                    ("time",L("Time remaining"))]
        case .gpu:
            return [("sparkline",L("History graph")), ("encoder",L("Encoder/Decoder")),
                    ("displays",L("Displays"))]
        case .bluetooth:
            return []
        }
    }
}

enum MenubarMetric: String, CaseIterable, Codable, Identifiable {
    case cpu, ram, network, battery, temperature

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cpu:         return L("CPU")
        case .ram:         return L("RAM")
        case .network:     return L("Network")
        case .battery:     return L("Battery")
        case .temperature: return L("Temp")
        }
    }

    var systemImage: String {
        switch self {
        case .cpu:         return "cpu"
        case .ram:         return "memorychip"
        case .network:     return "network"
        case .battery:     return "battery.100percent"
        case .temperature: return "thermometer.medium"
        }
    }
}

enum MenubarElement: String, Codable, CaseIterable, Identifiable {
    case icon, label, ring, sparkline, value, pressure

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .icon:      return L("Icon")
        case .label:     return L("Label")
        case .ring:      return L("Ring")
        case .sparkline: return L("Graph")
        case .value:     return "%"
        case .pressure:  return L("Pressure")
        }
    }

    var systemImage: String {
        switch self {
        case .icon:      return "square.on.square"
        case .label:     return "textformat"
        case .ring:      return "circle.circle"
        case .sparkline: return "waveform.path"
        case .value:     return "number"
        case .pressure:  return "gauge.with.needle"
        }
    }
}

struct MenubarItemConfig: Codable, Identifiable, Equatable {
    var metric: MenubarMetric
    var id: String { metric.rawValue }
    var enabled: Bool = true
    // Ordered list of elements to render for this metric
    var elements: [MenubarElement] = [.icon, .value]
    var customLabel: String = ""
    // Per-appearance tint: nil = system color (labelColor, adapts automatically)
    var darkTintHex: String? = nil    // used when macOS is in dark mode
    var lightTintHex: String? = nil   // used when macOS is in light mode
}

// MARK: - Card layout

enum CardLayoutMode: String, Codable, CaseIterable, Identifiable {
    case standard, compact, ring  // compact kept for migration; not shown in UI

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: return L("Standard")
        case .compact:  return L("Standard")
        case .ring:     return L("Ring gauge")
        }
    }

    var systemImage: String {
        switch self {
        case .standard, .compact: return "rectangle.expand.vertical"
        case .ring:               return "circle.circle"
        }
    }
}

struct CardConfig: Codable {
    var layoutMode: CardLayoutMode = .standard
    var accentHex: String? = nil
    // element key -> false means hidden; missing key means visible
    var elementVisibility: [String: Bool] = [:]

    func shows(_ element: String) -> Bool {
        elementVisibility[element] != false
    }
}

enum RefreshRate: Double, Codable, CaseIterable, Identifiable {
    case fast     = 1.0
    case normal   = 2.0
    case slow     = 5.0
    case verySlow = 10.0

    var id: Double { rawValue }

    var label: String {
        switch self {
        case .fast:     return "1s — " + L("Fast")
        case .normal:   return "2s — " + L("Normal")
        case .slow:     return "5s — " + L("Slow")
        case .verySlow: return "10s — " + L("Battery saver")
        }
    }
}

enum AppTheme: String, Codable, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return L("System")
        case .light:  return L("Light")
        case .dark:   return L("Dark")
        }
    }
}

// MARK: - Settings

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // Popover card order + visibility
    @Published var popoverCardOrder: [PopoverCard] {
        didSet { encode(popoverCardOrder, key: "popoverCardOrder") }
    }
    @Published var popoverCardEnabled: [String: Bool] {
        didSet { encode(popoverCardEnabled, key: "popoverCardEnabled") }
    }

    // Per-card configuration (layout mode, accent color, element visibility)
    @Published var cardConfigs: [String: CardConfig] {
        didSet { encode(cardConfigs, key: "cardConfigs") }
    }

    // Column assignments (card rawValue -> 0=left, 1=right) used in 2-column mode
    @Published var cardColumnAssignments: [String: Int] {
        didSet { encode(cardColumnAssignments, key: "cardColumnAssignments") }
    }

    // Menubar
    @Published var menubarItems: [MenubarItemConfig] {
        didSet { encode(menubarItems, key: "menubarItems") }
    }

    // General
    @Published var refreshRate: RefreshRate {
        didSet { encode(refreshRate, key: "refreshRate") }
    }
    @Published var menubarRefreshRate: RefreshRate {
        didSet { encode(menubarRefreshRate, key: "menubarRefreshRate") }
    }
    @Published var launchAtLogin: Bool {
        didSet { UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin") }
    }
    @Published var theme: AppTheme {
        didSet { encode(theme, key: "theme") }
    }
    @Published var language: AppLanguage {
        didSet {
            encode(language, key: "language")
            LocalizationManager.shared.apply(language)
        }
    }

    // Layout
    @Published var popoverColumns: Int {
        didSet { UserDefaults.standard.set(popoverColumns, forKey: "popoverColumns") }
    }
    @Published var popoverHeight: CGFloat {
        didSet { UserDefaults.standard.set(Double(popoverHeight), forKey: "popoverHeight") }
    }
    @Published var moodFaceEnabled: Bool {
        didSet { UserDefaults.standard.set(moodFaceEnabled, forKey: "moodFaceEnabled") }
    }
    @Published var popoutsEnabled: Bool {
        didSet { UserDefaults.standard.set(popoutsEnabled, forKey: "popoutsEnabled") }
    }
    @Published var bluetoothEnabled: Bool {
        didSet { UserDefaults.standard.set(bluetoothEnabled, forKey: "bluetoothEnabled") }
    }
    @Published var bluetoothShowOnlyConnected: Bool {
        didSet { UserDefaults.standard.set(bluetoothShowOnlyConnected, forKey: "bluetoothShowOnlyConnected") }
    }

    // Global hotkey (⌥Space)
    @Published var globalHotkeyEnabled: Bool {
        didSet { UserDefaults.standard.set(globalHotkeyEnabled, forKey: "globalHotkeyEnabled") }
    }

    // Auto-update
    @Published var autoUpdateCheck: Bool {
        didSet { UserDefaults.standard.set(autoUpdateCheck, forKey: "autoUpdateCheck") }
    }

    // Alerts
    @Published var topProcessesCount: Int {
        didSet { UserDefaults.standard.set(topProcessesCount, forKey: "topProcessesCount") }
    }

    @Published var alertsEnabled: Bool {
        didSet { UserDefaults.standard.set(alertsEnabled, forKey: "alertsEnabled") }
    }
    @Published var cpuAlertThreshold: Double {
        didSet { UserDefaults.standard.set(cpuAlertThreshold, forKey: "cpuAlertThreshold") }
    }
    @Published var ramAlertThreshold: Double {
        didSet { UserDefaults.standard.set(ramAlertThreshold, forKey: "ramAlertThreshold") }
    }
    @Published var tempAlertThreshold: Double {
        didSet { UserDefaults.standard.set(tempAlertThreshold, forKey: "tempAlertThreshold") }
    }
    var alertDebounceCount: Int = 5
    var alertCooldownSeconds: Double = 300

    private let defaults = UserDefaults.standard

    private init() {
        popoverCardOrder    = Self.decode([PopoverCard].self, key: "popoverCardOrder")
            ?? PopoverCard.allCases
        popoverCardEnabled  = Self.decode([String: Bool].self, key: "popoverCardEnabled")
            ?? Dictionary(uniqueKeysWithValues: PopoverCard.allCases.map { ($0.rawValue, true) })
        cardConfigs         = Self.decode([String: CardConfig].self, key: "cardConfigs") ?? [:]
        cardColumnAssignments = Self.decode([String: Int].self, key: "cardColumnAssignments")
            ?? Dictionary(uniqueKeysWithValues: PopoverCard.allCases.enumerated()
                .map { ($0.element.rawValue, $0.offset % 2) })
        menubarItems        = Self.decode([MenubarItemConfig].self, key: "menubarItems")
            ?? MenubarMetric.allCases.map { MenubarItemConfig(metric: $0) }
        refreshRate         = Self.decode(RefreshRate.self, key: "refreshRate") ?? .normal
        menubarRefreshRate  = Self.decode(RefreshRate.self, key: "menubarRefreshRate") ?? .verySlow
        launchAtLogin        = UserDefaults.standard.bool(forKey: "launchAtLogin")
        theme                = Self.decode(AppTheme.self, key: "theme") ?? .system
        language             = Self.decode(AppLanguage.self, key: "language") ?? .system
        popoverColumns       = UserDefaults.standard.object(forKey: "popoverColumns") as? Int ?? 1
        let savedH = UserDefaults.standard.double(forKey: "popoverHeight")
        popoverHeight = savedH > 0 ? CGFloat(savedH) : 560
        moodFaceEnabled      = UserDefaults.standard.object(forKey: "moodFaceEnabled") as? Bool ?? false
        popoutsEnabled       = UserDefaults.standard.object(forKey: "popoutsEnabled") as? Bool ?? true
        bluetoothEnabled              = UserDefaults.standard.object(forKey: "bluetoothEnabled") as? Bool ?? true
        bluetoothShowOnlyConnected    = UserDefaults.standard.object(forKey: "bluetoothShowOnlyConnected") as? Bool ?? false
        globalHotkeyEnabled  = UserDefaults.standard.object(forKey: "globalHotkeyEnabled") as? Bool ?? false
        autoUpdateCheck      = UserDefaults.standard.object(forKey: "autoUpdateCheck") as? Bool ?? true
        topProcessesCount    = UserDefaults.standard.object(forKey: "topProcessesCount") as? Int ?? 5
        alertsEnabled        = UserDefaults.standard.object(forKey: "alertsEnabled") as? Bool ?? true
        cpuAlertThreshold    = UserDefaults.standard.object(forKey: "cpuAlertThreshold") as? Double ?? 90
        ramAlertThreshold    = UserDefaults.standard.object(forKey: "ramAlertThreshold") as? Double ?? 85
        tempAlertThreshold   = UserDefaults.standard.object(forKey: "tempAlertThreshold") as? Double ?? 85
    }

    func isEnabled(_ card: PopoverCard) -> Bool {
        popoverCardEnabled[card.rawValue] ?? true
    }

    func setEnabled(_ card: PopoverCard, _ value: Bool) {
        popoverCardEnabled[card.rawValue] = value
    }

    var visibleCards: [PopoverCard] {
        popoverCardOrder.filter { isEnabled($0) }
    }

    func config(for card: PopoverCard) -> CardConfig {
        cardConfigs[card.rawValue] ?? CardConfig()
    }

    func setConfig(for card: PopoverCard, _ config: CardConfig) {
        cardConfigs[card.rawValue] = config
    }

    func column(for card: PopoverCard) -> Int {
        cardColumnAssignments[card.rawValue] ?? 0
    }

    func setColumn(for card: PopoverCard, _ col: Int) {
        cardColumnAssignments[card.rawValue] = col
    }

    // Cards for a given column, in their display order
    func cards(inColumn col: Int) -> [PopoverCard] {
        visibleCards.filter { column(for: $0) == col }
    }

    // Returns warning/critical color when value exceeds thresholds, otherwise the accent color.
    func thresholdColor(value: Double, threshold: Double, accent: Color) -> Color {
        let critical = min(threshold + 15, 99)
        if value >= critical { return .red }
        if value >= threshold { return .orange }
        return accent
    }

    // MARK: Persistence helpers

    private func encode<T: Encodable>(_ value: T, key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
