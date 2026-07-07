import Foundation
import Combine

final class AppState: ObservableObject {
    static let shared = AppState()

    let cpu       = CPUMonitor()
    let ram       = RAMMonitor()
    let battery   = BatteryMonitor()
    let processes = ProcessMonitor()
    let disk      = DiskMonitor()
    let network   = NetworkMonitor()
    let gpu       = GPUMonitor()
    let thermal   = ThermalMonitor()
    let bluetooth = BluetoothMonitor()

    let settings  = AppSettings.shared

    private var cancellables = Set<AnyCancellable>()

    private var popoverIsOpen = false

    private init() {
        settings.$refreshRate
            .dropFirst()
            .sink { [weak self] rate in
                guard let self, self.popoverIsOpen else { return }
                self.startAll(interval: rate.rawValue)
            }
            .store(in: &cancellables)
        settings.$menubarRefreshRate
            .dropFirst()
            .sink { [weak self] rate in
                guard let self, !self.popoverIsOpen else { return }
                self.startAllBackground()
            }
            .store(in: &cancellables)
        settings.$bluetoothEnabled
            .dropFirst()
            .sink { [weak self] enabled in
                guard let self else { return }
                let interval = popoverIsOpen
                    ? self.settings.refreshRate.rawValue
                    : self.settings.menubarRefreshRate.rawValue
                if enabled { self.bluetooth.start(interval: interval) }
                else       { self.bluetooth.stop() }
            }
            .store(in: &cancellables)
    }

    func startAll() {
        popoverIsOpen = true
        startAll(interval: settings.refreshRate.rawValue)
    }

    // Menubar-only rate — used when popover is closed
    func startAllBackground() {
        popoverIsOpen = false
        let interval = settings.menubarRefreshRate.rawValue
        cpu.start(interval: interval)
        ram.start(interval: interval)
        battery.start(interval: interval)
        processes.start(interval: interval)
        disk.start(interval: interval)
        network.start(interval: interval)
        gpu.start(interval: interval)
        thermal.start(interval: interval)
        if settings.bluetoothEnabled { bluetooth.start(interval: interval) }
    }

    func stopAll() {
        cpu.stop(); ram.stop(); battery.stop(); processes.stop()
        disk.stop(); network.stop(); gpu.stop(); thermal.stop(); bluetooth.stop()
    }

    private func startAll(interval: Double) {
        cpu.start(interval: interval)
        ram.start(interval: interval)
        battery.start(interval: interval)
        processes.start(interval: interval)
        disk.start(interval: interval)
        network.start(interval: interval)
        gpu.start(interval: interval)
        thermal.start(interval: interval)
        if settings.bluetoothEnabled { bluetooth.start(interval: interval) }
    }
}
