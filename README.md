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