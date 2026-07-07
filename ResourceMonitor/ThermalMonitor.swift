import Foundation
import IOKit

struct ThermalSensor: Identifiable, Equatable {
    let id: String      // SMC key
    let label: String
    let celsius: Double
}

struct FanInfo: Identifiable, Equatable {
    let id: Int         // fan index
    let rpm: Double
    let minRPM: Double
    let maxRPM: Double
    var percent: Double { maxRPM > minRPM ? (rpm - minRPM) / (maxRPM - minRPM) * 100 : 0 }
}

final class ThermalMonitor: ObservableObject, Monitor {
    @Published var sensors: [ThermalSensor] = []
    @Published var fans:    [FanInfo]       = []
    @Published var thermalState: String     = "Normal"
    @Published var cpuWatts:   Double = 0
    @Published var gpuWatts:   Double = 0
    @Published var aneWatts:   Double = 0   // Apple Neural Engine
    @Published var totalWatts: Double = 0   // Total package/system power
    @Published var pCoreGHz:   Double = 0
    @Published var eCoreGHz:   Double = 0
    @Published var voltageSensors: [ThermalSensor] = []
    /// Bitmask: bit N set means fan N is in manual mode.
    @Published var fanManualMask: UInt8 = 0
    /// Target RPM per fan index when in manual mode.
    @Published var fanTargetRPMs: [Int: Double] = [:]
    /// Whether SMC fan writes succeed on this machine.
    @Published var fanControlAvailable: Bool = false

    private let queue = DispatchQueue(label: "com.resourcemonitor.thermal", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var smc = SMCHelper()
    /// Discovered live temperature keys. Empty until first discovery run.
    private var discoveredKeys: [(key: String, label: String)] = []

    // Fallback key list used until dynamic discovery finishes.
    // Covers M1/M2 Apple Silicon and Intel chips.
    private let fallbackKeys: [(key: String, label: String)] = [
        ("Tp01", "CPU P-Core 1"), ("Tp05", "CPU P-Core 2"),
        ("Tp09", "CPU P-Core 3"), ("Tp0D", "CPU P-Core 4"),
        ("Tp0X", "CPU P-Core 5"), ("Tp0b", "CPU P-Core 6"),
        ("Tp0f", "CPU E-Core 1"), ("Tp0j", "CPU E-Core 2"),
        ("Tg05", "GPU"),          ("Tg0D", "GPU Die"),
        ("TB0T", "Battery"),      ("TB1T", "Battery 2"),
        ("Ts0S", "SoC"),
        ("TC0D", "Die"),          ("TC0P", "Proximity"),
        ("TA0P", "Ambient"),      ("TW0P", "Wi-Fi"),
    ]

    func start(interval: Double = 2.0) {
        let (pGHz, eGHz) = Self.readCPUFrequencies()
        DispatchQueue.main.async {
            self.pCoreGHz = pGHz
            self.eCoreGHz = eGHz
        }
        // open() is now idempotent — safe to call on every start()
        guard smc.open() else { return }

        // Discover all available temperature keys once (runs in background)
        if discoveredKeys.isEmpty {
            queue.async { [weak self] in self?.runDiscovery() }
        }

        stop()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: interval)
        t.setEventHandler { [weak self] in self?.update() }
        t.resume()
        timer = t
    }

    func stop() { timer?.cancel(); timer = nil }

    deinit {
        setAllFansAuto()
        smc.close()
    }

    // MARK: - Fan control

    func setFanManual(_ index: Int, rpm: Double) {
        guard smc.isOpen else { return }
        let newMask = fanManualMask | (1 << UInt8(index))
        let wrote = smc.writeUI16("FS! ", value: UInt16(newMask))
        guard wrote else {
            DispatchQueue.main.async { self.fanControlAvailable = false }
            return
        }
        let info = fans.first { $0.id == index }
        let clamped = min(max(rpm, info?.minRPM ?? 0), info?.maxRPM ?? 6000)
        smc.writeFPE2("F\(index)Tg", value: clamped)
        fanManualMask = newMask
        fanTargetRPMs[index] = clamped
        fanControlAvailable = true
    }

    func setFanAuto(_ index: Int) {
        guard smc.isOpen else { return }
        let newMask = fanManualMask & ~(1 << UInt8(index))
        guard smc.writeUI16("FS! ", value: UInt16(newMask)) else { return }
        fanManualMask = newMask
        fanTargetRPMs.removeValue(forKey: index)
    }

    func setAllFansAuto() {
        guard smc.isOpen, fanManualMask != 0 else { return }
        smc.writeUI16("FS! ", value: 0)
        fanManualMask = 0
        fanTargetRPMs.removeAll()
    }

    // MARK: - Discovery

    private func runDiscovery() {
        // Probe whether fan control SMC writes are permitted on this machine
        let canControl = smc.writeUI16("FS! ", value: 0)
        DispatchQueue.main.async { self.fanControlAvailable = canControl }

        // Enumerate all SMC keys to find active temperature sensors
        let total = smc.keyCount()
        guard total > 0 else { return }

        var found: [(key: String, label: String)] = []
        for i in 0..<total {
            guard let key = smc.keyAtIndex(UInt32(i)) else { continue }
            guard key.hasPrefix("T") else { continue }   // Temperature keys start with T
            guard let temp = smc.temperature(key), temp < 150 else { continue }
            // CPU/GPU sensors on a running Mac are always above ~20°C.
            // Keys returning less than that during discovery are likely non-temperature
            // config registers that happen to decode to a small float value.
            let isCpuGpu = key.hasPrefix("Tp") || key.hasPrefix("Tg") ||
                           key.hasPrefix("TC") || key.hasPrefix("Ts")
            let minDiscover = isCpuGpu ? 20.0 : 5.0
            guard temp >= minDiscover else { continue }
            found.append((key: key, label: labelForKey(key)))
        }
        if !found.isEmpty {
            DispatchQueue.main.async { self.discoveredKeys = found }
        }
    }

    private func labelForKey(_ key: String) -> String {
        let known: [String: String] = [
            "Tp01": "CPU P-Core 1", "Tp05": "CPU P-Core 2",
            "Tp09": "CPU P-Core 3", "Tp0D": "CPU P-Core 4",
            "Tp0X": "CPU P-Core 5", "Tp0b": "CPU P-Core 6",
            "Tp0f": "CPU E-Core 1", "Tp0j": "CPU E-Core 2",
            "Tp0P": "CPU P-Core",   "Tp0p": "CPU E-Core",
            "TpF0": "CPU Cluster",  "TpF1": "CPU Cluster 2",
            "Tg05": "GPU",          "Tg0D": "GPU Die",
            "TB0T": "Battery",      "TB1T": "Battery 2",
            "Ts0S": "SoC",          "TA0P": "Ambient",
            "TC0D": "CPU Die",      "TC0P": "CPU Prox",
            "TW0P": "Wi-Fi",
        ]
        if let l = known[key] { return l }
        if key.hasPrefix("Tp") { return "CPU \(key)" }
        if key.hasPrefix("Tg") { return "GPU \(key)" }
        if key.hasPrefix("TB") { return "Battery \(key)" }
        if key.hasPrefix("TC") { return "CPU \(key)" }
        return key
    }

    // MARK: - Update loop

    private var activeKeys: [(key: String, label: String)] {
        discoveredKeys.isEmpty ? fallbackKeys : discoveredKeys
    }

    // Known voltage SMC keys with labels
    private let voltageKeys: [(key: String, label: String)] = [
        ("VCFR", "CPU Core"),  ("VP0R", "5V Rail"),   ("VD0R", "3.3V Rail"),
        ("VG0C", "GPU Core"),  ("Vb0R", "Battery"),   ("VMNV", "Main 3V"),
        ("VN1R", "NVM 1.8V"),  ("VN0R", "NVM 3.3V"),
    ]

    private func update() {
        let cpuW  = smc.floatValue("PCPU") ?? smc.floatValue("Pcpu") ?? 0
        let gpuW  = smc.floatValue("PGPU") ?? smc.floatValue("Pgpu") ?? 0
        let aneW  = smc.floatValue("PANE") ?? smc.floatValue("Pane") ?? 0
        // Total package power: try PSTR (common), then PPKG, then sum of known consumers
        let totW: Double = {
            if let v = smc.floatValue("PSTR") ?? smc.floatValue("PPKG") { return v }
            let s = cpuW + gpuW + aneW
            return s > 0 ? s : 0
        }()

        // Voltage sensors — only include keys that return a plausible value
        let vSensors: [ThermalSensor] = voltageKeys.compactMap { entry in
            guard let v = smc.floatValue(entry.key), v > 0.1, v < 30 else { return nil }
            return ThermalSensor(id: "V_\(entry.key)", label: entry.label,
                                 celsius: v)  // reuse celsius field for voltage (in V)
        }

        // Snapshot the previous values so we can fall back per-sensor
        let prevMap = Dictionary(uniqueKeysWithValues: sensors.map { ($0.id, $0.celsius) })

        let foundSensors: [ThermalSensor] = activeKeys.compactMap { entry in
            let raw = smc.temperature(entry.key)
            let prev = prevMap[entry.key]

            let celsius: Double
            if let raw, raw >= 5.0, raw < 150.0 {
                // Reject a sudden implausible drop: if previous reading was a plausible
                // running temp (> 20°C) and the new value is suspiciously cold (< 15°C),
                // keep the previous value rather than flashing a bogus low reading.
                if let prev, prev > 20.0, raw < 15.0 {
                    celsius = prev
                } else {
                    celsius = raw
                }
            } else if let prev {
                celsius = prev   // SMC read failed — keep last-good for this sensor
            } else {
                return nil       // No previous value and no valid read — omit entirely
            }

            return ThermalSensor(id: entry.key, label: entry.label, celsius: celsius)
        }

        let count = smc.fanCount()
        let foundFans: [FanInfo] = (0..<count).compactMap { i in
            guard let rpm = smc.fanSpeed("F\(i)Ac") else { return nil }
            let minRPM = smc.fanSpeed("F\(i)Mn") ?? 0
            let maxRPM = smc.fanSpeed("F\(i)Mx") ?? 6000
            return FanInfo(id: i, rpm: rpm, minRPM: minRPM, maxRPM: maxRPM)
        }

        let state = readThermalState()

        DispatchQueue.main.async { [weak self] in
            if !foundSensors.isEmpty { self?.sensors = foundSensors }
            if !foundFans.isEmpty    { self?.fans    = foundFans }
            self?.thermalState    = state
            self?.cpuWatts        = cpuW
            self?.gpuWatts        = gpuW
            self?.aneWatts        = aneW
            self?.totalWatts      = totW
            if !vSensors.isEmpty  { self?.voltageSensors = vSensors }
        }
    }

    // MARK: - Static helpers

    private static func readCPUFrequencies() -> (Double, Double) {
        func mhz(_ key: String) -> Double {
            var val: UInt64 = 0
            var size = MemoryLayout<UInt64>.size
            sysctlbyname(key, &val, &size, nil, 0)
            return val > 0 ? Double(val) / 1_000_000_000 : 0
        }
        let p = mhz("hw.perflevel0.cpufrequency_max")
        let e = mhz("hw.perflevel1.cpufrequency_max")
        if p == 0 { return (mhz("hw.cpufrequency"), 0) }
        return (p, e)
    }

    private func readThermalState() -> String {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.thermal_level", &level, &size, nil, 0) != 0 {
            sysctlbyname("machdep.xcpm.cpu_thermal_level", &level, &size, nil, 0)
        }
        switch level {
        case 0:     return "Normal"
        case 1...3: return "Moderate"
        default:    return "Throttling"
        }
    }
}
