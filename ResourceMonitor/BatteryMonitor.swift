import Foundation
import IOKit
import IOKit.ps

final class BatteryMonitor: ObservableObject, Monitor {
    @Published var percent: Int = 0
    @Published var health: Int = 100
    @Published var condition: String = "Normal"
    @Published var isCharging: Bool = false
    @Published var isPluggedIn: Bool = false
    @Published var powerWatts: Double = 0
    @Published var adapterWatts: Int = 0
    @Published var chargerName: String = ""
    @Published var timeToEmptyMin: Int = -1   // -1 = unknown
    @Published var timeToFullMin: Int  = -1
    @Published var cycleCount: Int = 0
    @Published var maxCapacityMAh: Int = 0     // current max (after wear)
    @Published var designCapacityMAh: Int = 0  // original factory capacity
    @Published var macOSHealthPercent: Int = 0  // health % as shown in macOS Settings

    private let queue = DispatchQueue(label: "com.resourcemonitor.battery", qos: .utility)
    private var timer: DispatchSourceTimer?

    func start(interval: Double = 2.0) {
        stop()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: interval)
        t.setEventHandler { [weak self] in self?.update() }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func update() {
        let snap = readBattery()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.percent     = snap.percent
            self.health      = snap.health
            self.condition   = snap.condition
            self.isCharging  = snap.isCharging
            self.isPluggedIn = snap.isPluggedIn
            self.powerWatts  = snap.powerWatts
            self.adapterWatts = snap.adapterWatts
            self.chargerName      = snap.chargerName
            self.timeToEmptyMin   = snap.timeToEmptyMin
            self.timeToFullMin    = snap.timeToFullMin
            self.cycleCount        = snap.cycleCount
            self.maxCapacityMAh    = snap.maxCapacityMAh
            self.designCapacityMAh = snap.designCapacityMAh
            self.macOSHealthPercent = snap.macOSHealthPercent
        }
    }

    private struct Snapshot {
        var percent: Int = 0
        var health: Int = 100
        var condition: String = "Normal"
        var isCharging: Bool = false
        var isPluggedIn: Bool = false
        var powerWatts: Double = 0
        var adapterWatts: Int = 0
        var chargerName: String = ""
        var timeToEmptyMin: Int = -1
        var timeToFullMin:  Int = -1
        var cycleCount: Int = 0
        var maxCapacityMAh: Int = 0
        var designCapacityMAh: Int = 0
        var macOSHealthPercent: Int = 0
    }

    private func readBattery() -> Snapshot {
        var snap = Snapshot()

        let psInfo = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let psList = IOPSCopyPowerSourcesList(psInfo).takeRetainedValue() as [CFTypeRef]

        for source in psList {
            guard let desc = IOPSGetPowerSourceDescription(psInfo, source)
                    .takeUnretainedValue() as? [String: Any],
                  (desc[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }

            snap.percent     = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            snap.isCharging  = desc[kIOPSIsChargingKey] as? Bool ?? false
            snap.isPluggedIn = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            snap.condition   = desc["BatteryHealthCondition"] as? String ?? "Normal"
        }

        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return snap }
        defer { IOObjectRelease(service) }

        func intProp(_ key: String) -> Int {
            (IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Int) ?? 0
        }

        // Time remaining from IOKit (more accurate than IOPowerSources estimate)
        let timeEmpty = intProp("TimeRemaining")      // minutes, 65535 = unknown
        let timeFull  = intProp("AvgTimeToFull")      // minutes, 65535 = unknown
        snap.timeToEmptyMin = timeEmpty > 0 && timeEmpty < 65535 ? timeEmpty : -1
        snap.timeToFullMin  = timeFull  > 0 && timeFull  < 65535 ? timeFull  : -1

        snap.cycleCount = intProp("CycleCount")

        let rawMax    = intProp("AppleRawMaxCapacity")
        let designCap = intProp("DesignCapacity")
        if designCap > 0, rawMax > 0 {
            snap.health = min(100, Int(round(Double(rawMax) / Double(designCap) * 100)))
        }
        snap.maxCapacityMAh    = rawMax
        snap.designCapacityMAh = designCap
        snap.macOSHealthPercent = readMacOSHealthPercent()

        let ampMA  = intProp("Amperage")
        let voltMV = intProp("Voltage")
        snap.powerWatts = Double(ampMA) * Double(voltMV) / 1_000_000.0

        if let adapter = IORegistryEntryCreateCFProperty(
            service, "AdapterDetails" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any] {
            snap.adapterWatts = adapter["Watts"] as? Int ?? 0
            snap.chargerName  = (adapter["Name"] as? String) ?? "AC Adapter"
        } else {
            snap.chargerName = snap.isPluggedIn ? "AC Adapter" : ""
        }

        return snap
    }

    // Runs system_profiler to get the same health % macOS Settings shows.
    // Called from the background queue; takes ~0.5 s so we cache and only refresh every 60 s.
    private var cachedMacOSHealth: Int = 0
    private var lastHealthFetch: Date = .distantPast

    private func readMacOSHealthPercent() -> Int {
        guard Date().timeIntervalSince(lastHealthFetch) > 60 else { return cachedMacOSHealth }
        let out = shellOutput("/usr/sbin/system_profiler", ["SPPowerDataType"])
        for line in out.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("maximum capacity:"),
               let pctStr = trimmed.components(separatedBy: ":").last?
                                   .trimmingCharacters(in: .whitespaces)
                                   .replacingOccurrences(of: "%", with: ""),
               let pct = Int(pctStr) {
                cachedMacOSHealth = pct
                lastHealthFetch = Date()
                return pct
            }
        }
        return cachedMacOSHealth
    }
}
