import Foundation
import IOBluetooth

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

final class BluetoothMonitor: ObservableObject, Monitor {
    @Published var devices: [BluetoothDevice] = []

    private let queue = DispatchQueue(label: "com.resourcemonitor.bluetooth", qos: .utility)
    private var timer: DispatchSourceTimer?

    func start(interval: Double = 2.0) {
        stop()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: max(interval, 5))
        t.setEventHandler { [weak self] in self?.update() }
        t.resume()
        timer = t
    }

    func stop() { timer?.cancel(); timer = nil }

    private func update() {
        // IOBluetooth calls must happen on the main thread
        DispatchQueue.main.async { [weak self] in
            self?.readDevices()
        }
    }

    private func readDevices() {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return }

        devices = paired.compactMap { device -> BluetoothDevice? in
            guard let name = device.name, !name.isEmpty else { return nil }
            // Use address as stable ID; fall back to name (more stable than a new UUID each tick)
            let addr      = device.addressString ?? name
            let connected = device.isConnected()
            let battery   = batteryLevel(device)
            let category  = classify(device)
            return BluetoothDevice(id: addr, name: name, category: category,
                                   isConnected: connected, batteryPercent: battery)
        }
        .sorted { $0.isConnected && !$1.isConnected }
    }

    private func batteryLevel(_ device: IOBluetoothDevice) -> Int {
        // Private IOBluetooth battery properties are blocked by the runtime on macOS 14+.
        // Return unknown until a public API is available.
        return -1
    }

    private func classify(_ device: IOBluetoothDevice) -> BluetoothDevice.Category {
        let name  = (device.name ?? "").lowercased()
        let clazz = Int(device.classOfDevice)

        // Major device class from Bluetooth CoD
        let major = (clazz >> 8) & 0x1F
        switch major {
        case 4: // Audio/Video — all peripherals in this class map to headphones
            return .headphones
        case 5: // Peripheral
            let minor = (clazz >> 2) & 0x3F
            switch minor {
            case 0x01...0x03: return .keyboard
            case 0x04...0x06: return .mouse
            case 0x07:        return .trackpad
            default:          break
            }
        case 8: return .controller
        default: break
        }
        // Name-based fallback
        if name.contains("keyboard") { return .keyboard }
        if name.contains("mouse")    { return .mouse }
        if name.contains("trackpad") { return .trackpad }
        if name.contains("airpod") || name.contains("headphone") || name.contains("beats") {
            return .headphones
        }
        return .unknown
    }
}
