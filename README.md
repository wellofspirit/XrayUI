# XrayUI

XrayUI is a lightweight macOS menu bar application designed to manage [Xray-core](https://github.com/XTLS/Xray-core) easily. It provides a convenient interface to control the Xray service, manage configurations, and view logs directly from your status bar.

## Features

- **Menu Bar Integration**: Unobtrusive status icon indicating service state (Running/Stopped).
- **Service Control**: One-click Start and Stop functionality.
- **Configuration Management**:
  - Switch between multiple configuration files on the fly.
  - Generate example configuration (`config.json`).
  - Quick access to the configuration folder.
- **Log Viewer**:
  - Real-time log monitoring with auto-scroll.
  - View historical log files.
  - Built-in search functionality.
- **Automatic Updates**: Automatically checks for and downloads the latest compatible Xray-core binary from GitHub.

## Getting Started

1. **Launch the App**: The app will appear in your menu bar.
2. **Initial Setup**:
   - On first launch, if no config exists, you can use **Configs > Generate Example Config** to create a basic template.
   - Alternatively, place your `config.json` files in the `Application Support/com.daniel.xray-service/configs` directory (accessible via **Configs > Open Configs in Finder**).
3. **Start Service**: Click **Start Service** from the menu.

## Requirements

- macOS 14.0 or later.
- Internet connection (for extracting Xray-core updates).