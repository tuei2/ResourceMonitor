# ResourceMonitor

A native macOS menu bar app for real-time system monitoring — CPU, memory, network, disk, GPU, battery, Bluetooth, and thermals — in a clean popover with hover detail panels.

## Screenshots

| Dashboard | Detail panel |
|-----------|--------------|
| ![Dashboard](docs/screenshots/dashboard.png) | ![Detail panel](docs/screenshots/detail.png) |

| Settings | Menu bar |
|----------|----------|
| ![Settings](docs/screenshots/settings.png) | ![Menu bar](docs/screenshots/menubar.png) |

## Features

- **CPU** — usage, per-core and P/E-core clusters, top processes, load averages
- **Memory** — used/wired/compressed/free breakdown, pressure, swap, top processes
- **Network** — up/down throughput, butterfly chart, Wi-Fi/Ethernet detection, VPN indicator, Wi-Fi signal, local & public IP, daily usage
- **Disk** — read/write throughput, volumes, per-process I/O
- **GPU** — utilization, renderer/tiler/encoder/decoder, VRAM, connected displays & resolutions
- **Battery** — charge, power-flow diagram, capacity/health, cycles, time remaining
- **Bluetooth** — connected/paired devices with battery levels
- **Thermals** — CPU/GPU/battery temperatures, sensors, fan speeds
- **MoodFace** — an optional menu bar emoji reflecting your Mac's current mood
- **Configurable menu bar** — pick metrics, elements (icon/label/ring/graph/value), per-appearance tint colors
- **Multilingual** — English & Dutch, switchable live in Settings (no restart)
- **Auto-update** — checks GitHub Releases and offers to download newer versions

## Requirements

- macOS 14+
- Apple Silicon or Intel

## Building

Open `ResourceMonitor.xcodeproj` in Xcode and build the `ResourceMonitor` scheme, or:

```bash
xcodebuild -project ResourceMonitor.xcodeproj -scheme ResourceMonitor -configuration Release build
```

## Updates

The app checks [GitHub Releases](https://github.com/tuei2/ResourceMonitor/releases) for new versions on launch (at most once per day) and can be triggered manually from **Settings → General → Updates**. See [RELEASING.md](RELEASING.md) for how releases are published.

## License

© 2026 tuei2. All rights reserved.
