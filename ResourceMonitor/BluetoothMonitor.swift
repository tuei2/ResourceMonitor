import Foundation
import AppKit
import CoreBluetooth

struct BluetoothDevice: Identifiable, Equatable {
    let id: String          // address string
    let name: String
    let category: Category
    let isConnected: Bool
    let batteryPercent: Int // -1 = unknown

    enum Category {
        case headphones, keyboard, mouse, trackpad, controller, unknown
        var systemImage: String {
            switch self {
            case .headphones: return "headphones"
            case .keyboard:   return "keyboard"
            case .mouse:      return "computermouse"
            case .trackpad:   return "rectangle.and.hand.point.up.left"
            case .controller: return "gamecontroller"
            case .unknown:    return "dot.radiowaves.left.and.right"
            }
        }
    }
}

/// High-level Bluetooth power/permission state for the UI.
enum BluetoothPermission: Equatable {
    case unknown       // not yet determined
    case authorized    // available and readable
    case denied        // user denied CoreBluetooth access
    case unsupported   // no Bluetooth hardware or powered off
}

/// Reads paired/connected Bluetooth devices and their battery levels from
/// `system_profiler SPBluetoothDataType`, which — unlike IOBluetooth on
/// macOS 14+ — needs no Bluetooth TCC grant and never crashes on a privacy
/// violation. CoreBluetooth is used only to report power/permission state.
final class BluetoothMonitor: NSObject, ObservableObject, Monitor {
    @Published var devices: [BluetoothDevice] = []
    @Published var permission: BluetoothPermission = .unknown

    private let queue = DispatchQueue(label: "com.resourcemonitor.bluetooth", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var central: CBCentralManager?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil,
                                   options: [CBCentralManagerOptionShowPowerAlertKey: false])
        refreshPermission()
    }

    func start(interval: Double = 2.0) {
        stop()
        // system_profiler is relatively slow, so never poll faster than 5s.
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: max(interval, 5))
        t.setEventHandler { [weak self] in self?.update() }
        t.resume()
        timer = t
    }

    func stop() { timer?.cancel(); timer = nil }

    /// Opens the Bluetooth privacy pane so the user can grant access.
    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Permission / power state

    private func refreshPermission() {
        let auth = CBManager.authorization
        let state = central?.state ?? .unknown
        let newState: BluetoothPermission
        switch auth {
        case .denied, .restricted:
            newState = .denied
        case .allowedAlways, .notDetermined:
            // system_profiler works regardless of the CoreBluetooth grant;
            // only surface a problem when the radio is off/absent.
            newState = (state == .poweredOff || state == .unsupported) ? .unsupported : .authorized
        @unknown default:
            newState = .authorized
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.permission != newState else { return }
            self.permission = newState
        }
    }

    // MARK: - Reading

    /// One-shot device read, independent of the polling timer. Called when the
    /// card appears and when CoreBluetooth becomes ready, so devices show even
    /// when periodic Bluetooth polling (`bluetoothEnabled`) is turned off.
    func refreshOnce() {
        queue.async { [weak self] in self?.update() }
    }

    private func update() {
        let list = Self.fetchDevices()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshPermission()
            self.devices = list
        }
    }

    // MARK: - system_profiler parsing

    private static func fetchDevices() -> [BluetoothDevice] {
        guard let root = runSystemProfiler(),
              let blocks = root["SPBluetoothDataType"] as? [[String: Any]] else { return [] }

        var result: [BluetoothDevice] = []
        for block in blocks {
            result += parse(block["device_connected"], connected: true)
            result += parse(block["device_not_connected"], connected: false)
        }
        return result.sorted { $0.isConnected && !$1.isConnected }
    }

    private static func parse(_ list: Any?, connected: Bool) -> [BluetoothDevice] {
        guard let entries = list as? [[String: Any]] else { return [] }
        return entries.compactMap { entry -> BluetoothDevice? in
            guard let (name, value) = entry.first,
                  let props = value as? [String: Any] else { return nil }
            let addr = (props["device_address"] as? String) ?? name
            return BluetoothDevice(
                id: addr,
                name: name,
                category: category(minorType: props["device_minorType"] as? String, name: name),
                isConnected: connected,
                batteryPercent: batteryPercent(from: props)
            )
        }
    }

    private static func batteryPercent(from props: [String: Any]) -> Int {
        func value(_ key: String) -> Int? {
            guard let s = props[key] as? String else { return nil }
            return Int(s.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces))
        }
        if let main = value("device_batteryLevelMain") { return main }
        let sides = [value("device_batteryLevelLeft"), value("device_batteryLevelRight")].compactMap { $0 }
        return sides.min() ?? -1
    }

    private static func category(minorType: String?, name: String) -> BluetoothDevice.Category {
        switch minorType?.lowercased() {
        case "keyboard":            return .keyboard
        case "mouse":               return .mouse
        case "trackpad":            return .trackpad
        case "headphones", "headset", "speaker": return .headphones
        case "gamepad", "controller", "joystick": return .controller
        default: break
        }
        let n = name.lowercased()
        if n.contains("keyboard") { return .keyboard }
        if n.contains("mouse")    { return .mouse }
        if n.contains("trackpad") { return .trackpad }
        if n.contains("airpod") || n.contains("headphone") || n.contains("beats") { return .headphones }
        return .unknown
    }

    /// Runs system_profiler via the shared `shellOutput` helper — the same path
    /// used elsewhere in the app for system_profiler — and returns the parsed JSON.
    private static func runSystemProfiler() -> [String: Any]? {
        let out = shellOutput("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"], timeout: 15)
        guard let data = out.data(using: .utf8), !data.isEmpty else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothMonitor: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        refreshPermission()
        // Initial read so devices appear on launch even if periodic polling is off.
        refreshOnce()
    }
}
