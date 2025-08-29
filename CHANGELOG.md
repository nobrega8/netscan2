# Changelog

## Version 1.2 (Current)

### Fixed Issues
- Fixed duplicate unknown network creation - now reuses existing unknown networks based on interface IP instead of creating new ones with timestamps
- Improved SSID detection to prevent unnecessary network duplication

### New Features
- **Status Column**: Added online/offline status indicator for devices
  - Green circle + "online" for devices found in current scan
  - Red circle + "offline" for devices not found in current scan
  - Visual status indicators in device list

- **Device Selection and Merge**: 
  - Multi-select devices in the device list
  - Merge selected devices (useful for devices with multiple MAC addresses like 2.4G/5G interfaces)
  - Selection counter and controls in toolbar

- **Dynamic OUI Management**:
  - When editing device brands, the OUI-brand mapping is automatically saved
  - Custom OUI mappings stored in `~/Library/Application Support/NetScan/oui.json`
  - Extends the brand detection database dynamically

### Improvements
- Updated CSV export to include status column
- Enhanced device management with better offline/online tracking
- Improved network persistence to avoid duplicate unknown networks

### Technical Changes
- Added `status` field to Device model
- Modified `addOrUpdateNetwork()` to track online/offline status
- Enhanced `OUIManager` with `addCustomOUI()` method
- Improved `getOrCreateUnknownNetworkName()` to reuse networks
- Added device selection and merge functionality to UI
- Updated project version to 1.2