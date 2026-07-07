# Changelog

All notable changes to ResourceMonitor are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Wi-Fi name and signal strength (dBm/RSSI) now request Location access, which
  macOS requires; a hint with a shortcut to System Settings shows when it's denied.
- Screenshots section in the README.

### Fixed
- Network card IP addresses no longer wrap mid-value when the VPN badge is shown;
  they stay on one line and keep priority over the header badge.
- The "VPN active" badge no longer stretches tall when space is tight (keeps its
  natural size), and the menu-bar VPN icon uses a better-proportioned glyph.
- History (CPU, memory, GPU, network, disk) now persists across app restarts:
  it is saved on quit and restored for up to 8 days, so the day/week graphs are
  no longer a flat line after reopening. CPU history is now persisted too.

## [1.0.1] - 2026-07-07

### Added
- Settings **About** tab showing the app version and build, GitHub links, and a
  manual update check.

### Changed
- Bluetooth devices and battery levels are now read entirely from
  `system_profiler`, which needs no Bluetooth permission and avoids an
  IOBluetooth privacy-violation crash on macOS 14+. CoreBluetooth is used only to
  detect when the radio is off.

### Fixed
- Bluetooth devices no longer appeared on macOS 14+, and battery levels (including
  per-side AirPods levels) are now shown for devices that report them.
- The Bluetooth card now refreshes when it appears, so devices are listed even
  when periodic Bluetooth polling is turned off in settings.

## [1.0.0] - 2026-07-07

### Added
- Initial public release.
- Menu bar monitoring for CPU, memory, network, disk, GPU, battery, Bluetooth, and thermals.
- Popover dashboard with per-card hover detail panels and optional popout windows.
- Network: butterfly chart, Wi-Fi/Ethernet connection-type detection, VPN indicator, Wi-Fi signal, local & public IP, daily usage.
- GPU: connected displays with native resolution and refresh rate.
- Battery: power-flow diagram, capacity/health (system_profiler), cycles, time remaining.
- MoodFace: optional menu bar emoji with a humorous system diagnosis.
- Configurable menu bar items (metrics, elements, per-appearance tint colors).
- English & Dutch localization, switchable live in Settings.
- Automatic update checks against GitHub Releases.

[Unreleased]: https://github.com/tuei2/ResourceMonitor/compare/v1.0.1...HEAD
[1.0.1]: https://github.com/tuei2/ResourceMonitor/releases/tag/v1.0.1
[1.0.0]: https://github.com/tuei2/ResourceMonitor/releases/tag/v1.0.0
