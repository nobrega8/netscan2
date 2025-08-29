# NetScan2 - Enhanced Network Scanner

A SwiftUI network scanner for macOS with Wi-Fi network persistence and enhanced device management.

## Features

### 🛜 Wi-Fi Network Persistence
- Automatically detects and stores Wi-Fi networks by SSID
- Each network maintains its own device list
- Customizable emoji for each network
- Persistent storage in Application Support directory

### 📱 Enhanced Device Management  
- **Owner**: Manually editable field to track device ownership
- **Brand**: Automatically detected from MAC address via OUI lookup
- **Model**: Manually editable field for device model information
- In-line editing of device properties
- Drag & drop PNG icons for custom device icons

### 🔍 OUI Brand Detection
- Built-in database of common vendor MAC prefixes
- Automatic brand detection for Apple, TP-Link, Xiaomi, Samsung, ASUS, Netgear, Linksys, Amazon, Google devices
- Support for user-provided `oui.json` file for extended brand database

### 💾 Data Persistence
- Networks and devices stored in JSON format
- Location: `~/Library/Application Support/NetScan/`
- Files: `networks.json`, `icons.json`, optional `oui.json`

### 🖥️ Modern UI
- NavigationSplitView with network sidebar
- Device list with sortable columns
- Context menus for quick actions
- Real-time scan progress indicators

## Usage

1. **Network Selection**: Choose a Wi-Fi network from the sidebar
2. **Scan Devices**: Click "Scan" to discover devices on the selected network  
3. **Edit Device Info**: Click on owner, brand, or model fields to edit
4. **Customize Icons**: Drag PNG files onto device rows for custom icons
5. **Network Emojis**: Click network emoji in sidebar to customize

## Installation

### Running from Source
1. Clone this repository
2. Open `netscan2.xcodeproj` in Xcode
3. Build and run the project (⌘+R)
4. Grant network permissions when prompted

### Distribution Build
For distribution outside the Mac App Store:
1. Archive the project in Xcode (Product → Archive)
2. Export as "Developer ID" signed application
3. Distribute the `.app` bundle to users
4. Users may need to allow the app in System Preferences → Security & Privacy

### First Launch
- The app will request permission to access network information
- On first scan, it will automatically detect your current Wi-Fi network
- Device data is stored locally in `~/Library/Application Support/NetScan/`

## Data Storage

### Networks File (`networks.json`)
```json
[
  {
    "id": "uuid",
    "ssid": "My Network", 
    "emoji": "🏠",
    "devices": {
      "AA:BB:CC:DD:EE:FF": {
        "ip": "192.168.1.100",
        "mac": "AA:BB:CC:DD:EE:FF",
        "hostname": "iPhone",
        "owner": "João",
        "brand": "Apple", 
        "model": "iPhone 14",
        "lastSeen": "2025-01-01T00:00:00Z"
      }
    },
    "lastSeen": "2025-01-01T00:00:00Z"
  }
]
```

### Custom OUI Database (`oui.json`)
Place in `~/Library/Application Support/NetScan/oui.json`:
```json
{
  "00:1B:63": "Apple",
  "50:C7:BF": "TP-Link",
  "34:CE:00": "Xiaomi"
}
```

## CSV Export

Export includes all device fields:
- IP Address
- MAC Address  
- Hostname
- Owner
- Brand
- Model

## Requirements

- macOS 12.0 or later
- SwiftUI framework
- CoreWLAN framework (for SSID detection)

## Known Limitations

- **Network Permissions**: The app requires network permissions to perform ping and ARP operations for device discovery
- **Sandboxed Environment**: When running in App Store sandbox mode, some network operations may be restricted
- **Root Privileges**: Advanced network scanning features may require elevated permissions for optimal performance
- **Network Types**: Best performance on Wi-Fi networks; Ethernet connections are supported but appear as "Desconhecida" (Unknown)

## Roadmap

Future features planned for upcoming releases:

### 🔍 Enhanced Filtering & Search
- Advanced device filtering by type, brand, or status
- Search across multiple networks simultaneously
- Custom device grouping and tagging

### 📊 Export & Reporting  
- Multiple export formats (CSV, JSON, XML)
- Network topology visualization
- Device history and change tracking

### 🔔 Notifications & Monitoring
- Real-time device connect/disconnect notifications
- Scheduled automatic scans
- Security alerts for new unknown devices

### 🛡️ Security Features
- Device security assessment
- Port scanning capabilities
- Network vulnerability detection

### 🎨 UI/UX Improvements
- Dark mode support refinements
- Customizable device view layouts
- Network map visualization