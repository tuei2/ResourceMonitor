# Changelog

All notable changes to ResourceMonitor are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- Bluetooth devices no longer appeared on macOS 14+ because the app never
  requested Bluetooth authorization. The app now requests and checks CoreBluetooth
  permission and shows a notice with a shortcut to System Settings when access is
  denied.

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

[Unreleased]: https://github.com/tuei2/ResourceMonitor/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/tuei2/ResourceMonitor/releases/tag/v1.0.0
