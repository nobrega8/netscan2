import SwiftUI
import Network
import SystemConfiguration
import CoreWLAN
import UniformTypeIdentifiers

// MARK: - Models

struct WiFiNetwork: Identifiable, Codable, Hashable {
    let id = UUID()
    let ssid: String
    var emoji: String
    var devices: [String: Device] // MAC address -> Device
    var lastSeen: Date
    
    init(ssid: String, emoji: String = "🛜") {
        self.ssid = ssid
        self.emoji = emoji
        self.devices = [:]
        self.lastSeen = Date()
    }
    
    var deviceCount: Int {
        devices.count
    }
}

struct Device: Identifiable, Codable, Hashable {
    let id = UUID()
    let ip: String
    let mac: String?
    let hostname: String?
    var customIconPath: String? // PNG por MAC (se existir)
    
    // New fields for enhanced device management
    var owner: String // Dono - editable by user
    var brand: String // Marca - auto-filled via OUI, editable
    var model: String // Modelo - editable by user
    var lastSeen: Date
    
    init(ip: String, mac: String?, hostname: String?, customIconPath: String? = nil) {
        self.ip = ip
        self.mac = mac
        self.hostname = hostname
        self.customIconPath = customIconPath
        self.owner = ""
        self.brand = ""
        self.model = ""
        self.lastSeen = Date()
    }
    
    var displayName: String {
        if let hn = hostname, !hn.isEmpty, hn != ip { return hn }
        return ip
    }
    
    var iconEmoji: String {
        // Emoji heurístico muito simples; personaliza à vontade
        if let hn = hostname?.lowercased() {
            if hn.contains("iphone") || hn.contains("ipad") { return "📱" }
            if hn.contains("mac") || hn.contains("imac") || hn.contains("mbp") { return "💻" }
            if hn.contains("tv") { return "📺" }
            if hn.contains("printer") || hn.contains("hp") { return "🖨️" }
            if hn.contains("cam") { return "📷" }
            if hn.contains("router") || hn.contains("gw") { return "🛜" }
        }
        return "🖥️"
    }
    
    // Create updated device with new scan data while preserving user fields
    func updatedFromScan(ip: String, hostname: String?, customIconPath: String?, brand: String) -> Device {
        var updated = Device(ip: ip, mac: self.mac, hostname: hostname, customIconPath: customIconPath)
        
        // Preserve user-editable fields
        updated.owner = self.owner
        updated.model = self.model
        
        // Preserve manually set brand, otherwise use detected brand
        updated.brand = self.brand.isEmpty ? brand : self.brand
        
        // Preserve custom icon if not provided in scan
        if customIconPath == nil {
            updated.customIconPath = self.customIconPath
        }
        
        return updated
    }
}

// MARK: - OUI Manager (for Brand Detection)

final class OUIManager {
    static let shared = OUIManager()
    
    private init() {}
    
    // Common OUI prefixes for popular brands
    private let commonOUIs: [String: String] = [
        "00:1B:63": "Apple",
        "00:1F:F3": "Apple", 
        "00:25:00": "Apple",
        "3C:15:C2": "Apple",
        "AC:DE:48": "Apple",
        "B8:E8:56": "Apple",
        "DC:A6:32": "Apple",
        "E4:CE:8F": "Apple",
        "F0:18:98": "Apple",
        "F4:0F:24": "Apple",
        "F8:1E:DF": "Apple",
        "F8:FF:C2": "Apple",
        
        "50:C7:BF": "TP-Link",
        "C4:E9:84": "TP-Link",
        "EC:08:6B": "TP-Link",
        "F4:F2:6D": "TP-Link",
        
        "34:CE:00": "Xiaomi",
        "50:8F:4C": "Xiaomi",
        "68:DF:DD": "Xiaomi",
        "8C:BE:BE": "Xiaomi",
        "F8:59:71": "Xiaomi",
        
        "00:24:D4": "Samsung",
        "08:EC:A9": "Samsung",
        "3C:8B:FE": "Samsung",
        "CC:07:AB": "Samsung",
        "E8:5B:5B": "Samsung",
        
        "B4:0B:44": "ASUS",
        "1C:B7:2C": "ASUS",
        "2C:56:DC": "ASUS",
        "AC:9E:17": "ASUS",
        
        "00:26:B0": "Netgear",
        "28:C6:8E": "Netgear",
        "A0:04:60": "Netgear",
        "E0:46:9A": "Netgear",
        
        "00:16:B6": "Linksys",
        "48:F8:B3": "Linksys",
        "C4:41:1E": "Linksys",
        
        "D8:50:E6": "Amazon",
        "FC:A6:67": "Amazon",
        "F0:D2:F1": "Amazon",
        
        "18:B4:30": "Google",
        "AA:8E:78": "Google",
        "F4:F5:DB": "Google"
    ]
    
    func getBrand(fromMAC mac: String) -> String {
        let cleanMAC = mac.uppercased().replacingOccurrences(of: "-", with: ":")
        
        // Extract first 8 characters (first 3 octets) for OUI lookup
        let oui = String(cleanMAC.prefix(8))
        
        if let brand = commonOUIs[oui] {
            return brand
        }
        
        // Try to load from user's oui.json file if it exists
        if let userBrand = lookupUserOUI(oui: oui) {
            return userBrand
        }
        
        return ""
    }
    
    private func lookupUserOUI(oui: String) -> String? {
        // Try to load user-provided oui.json file
        let fm = FileManager.default
        guard let appSupportDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let netScanDir = appSupportDir.appendingPathComponent("NetScan", isDirectory: true)
        let ouiFile = netScanDir.appendingPathComponent("oui.json")
        
        guard let data = try? Data(contentsOf: ouiFile),
              let ouiDict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return nil
        }
        
        return ouiDict[oui]
    }
}

// MARK: - Network Manager (for Network Persistence)

final class NetworkManager: ObservableObject {
    static let shared = NetworkManager()
    
    @Published var networks: [WiFiNetwork] = []
    @Published var selectedNetworkId: UUID?
    
    private let fm = FileManager.default
    
    private init() {
        loadNetworks()
    }
    
    private var appSupportDir: URL {
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Unable to access Application Support directory")
        }
        let dir = base.appendingPathComponent("NetScan", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    private var networksURL: URL {
        appSupportDir.appendingPathComponent("networks.json")
    }
    
    private func loadNetworks() {
        do {
            let data = try Data(contentsOf: networksURL)
            let networks = try JSONDecoder().decode([WiFiNetwork].self, from: data)
            self.networks = networks
        } catch {
            // If loading fails, start with empty networks list
            print("Failed to load networks: \(error.localizedDescription)")
            self.networks = []
        }
    }
    
    private func saveNetworks() {
        do {
            let data = try JSONEncoder().encode(networks)
            try data.write(to: networksURL, options: .atomic)
        } catch {
            print("Failed to save networks: \(error.localizedDescription)")
        }
    }
    
    func getCurrentSSID() -> String? {
        // Get current Wi-Fi network SSID using CoreWLAN framework
        do {
            guard let wifiInterface = CWWiFiClient.shared().interface() else {
                // No Wi-Fi interface available (e.g., using Ethernet)
                return nil
            }
            
            guard let ssid = wifiInterface.ssid(), !ssid.isEmpty else {
                // Wi-Fi interface exists but not connected to a network
                return nil
            }
            
            return ssid
        } catch {
            // If CoreWLAN fails, return nil to indicate unknown network
            print("Failed to get Wi-Fi SSID: \(error)")
            return nil
        }
    }
    
    func addOrUpdateNetwork(ssid: String, devices: [Device]) {
        if let index = networks.firstIndex(where: { $0.ssid == ssid }) {
            // Update existing network
            var network = networks[index]
            
            // Merge devices - existing devices keep user data, new devices get auto-detected data
            for device in devices {
                if let mac = device.mac {
                    if let existingDevice = network.devices[mac] {
                        // Create updated device while preserving user fields
                        let updatedDevice = existingDevice.updatedFromScan(
                            ip: device.ip,
                            hostname: device.hostname,
                            customIconPath: device.customIconPath,
                            brand: device.brand
                        )
                        network.devices[mac] = updatedDevice
                    } else {
                        // New device
                        network.devices[mac] = device
                    }
                }
            }
            
            network.lastSeen = Date()
            networks[index] = network
        } else {
            // Create new network
            var network = WiFiNetwork(ssid: ssid)
            for device in devices {
                if let mac = device.mac {
                    network.devices[mac] = device
                }
            }
            networks.append(network)
        }
        
        saveNetworks()
    }
    
    func updateNetworkEmoji(_ networkId: UUID, emoji: String) {
        if let index = networks.firstIndex(where: { $0.id == networkId }) {
            networks[index].emoji = emoji
            saveNetworks()
        }
    }
    
    func updateDevice(_ device: Device, in networkId: UUID) {
        guard let networkIndex = networks.firstIndex(where: { $0.id == networkId }),
              let mac = device.mac else { return }
        
        networks[networkIndex].devices[mac] = device
        saveNetworks()
    }
    
    func getSelectedNetwork() -> WiFiNetwork? {
        guard let selectedId = selectedNetworkId else { return nil }
        return networks.first { $0.id == selectedId }
    }
    
    func getDevicesForSelectedNetwork() -> [Device] {
        guard let network = getSelectedNetwork() else { return [] }
        return Array(network.devices.values).sorted { ipLess($0.ip, $1.ip) }
    }
}

// MARK: - Icon Manager (for PNG icons by MAC)

final class IconManager {
    static let shared = IconManager()
    private let mappingKey = "iconMappingByMAC"
    private let fm = FileManager.default
    
    private init() {}
    
    private var appSupportDir: URL {
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Unable to access Application Support directory")
        }
        let dir = base.appendingPathComponent("NetScan", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    private var mappingURL: URL { appSupportDir.appendingPathComponent("icons.json") }
    
    private func loadMapping() -> [String:String] {
        guard let data = try? Data(contentsOf: mappingURL),
              let dict = try? JSONDecoder().decode([String:String].self, from: data) else { return [:] }
        return dict
    }
    
    private func saveMapping(_ dict: [String:String]) {
        if let data = try? JSONEncoder().encode(dict) {
            try? data.write(to: mappingURL, options: .atomic)
        }
    }
    
    func iconPath(forMAC mac: String) -> String? {
        loadMapping()[mac.uppercased()]
    }
    
    func setIcon(forMAC mac: String, imageURL: URL) {
        // Copia PNG para App Support com nome MAC.png
        let dest = appSupportDir.appendingPathComponent(mac.uppercased() + ".png")
        try? fm.removeItem(at: dest)
        try? fm.copyItem(at: imageURL, to: dest)
        var map = loadMapping()
        map[mac.uppercased()] = dest.path
        saveMapping(map)
    }
    
    func removeIcon(forMAC mac: String) {
        var map = loadMapping()
        if let path = map[mac.uppercased()] {
            try? fm.removeItem(atPath: path)
        }
        map.removeValue(forKey: mac.uppercased())
        saveMapping(map)
    }
}

// MARK: - Networking utils

enum NetUtils {
    struct InterfaceInfo {
        let ip: String
        let netmask: String
    }
    
    static func getPrimaryIPv4() -> InterfaceInfo? {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let start = ifaddrPtr else { return nil }
        defer { freeifaddrs(ifaddrPtr) }
        
        var best: InterfaceInfo?

        var ptrOpt: UnsafeMutablePointer<ifaddrs>? = start
        while let ptr = ptrOpt {
            defer { ptrOpt = ptr.pointee.ifa_next }
            let ifa = ptr.pointee
            let flags = Int32(ifa.ifa_flags)
            if (flags & (IFF_UP|IFF_RUNNING|IFF_LOOPBACK)) != (IFF_UP|IFF_RUNNING) { continue }
            guard ifa.ifa_addr.pointee.sa_family == sa_family_t(AF_INET) else { continue }

            var addr = ifa.ifa_addr.pointee
            var mask = ifa.ifa_netmask.pointee
            var ipBuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            var nmBuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(&addr, socklen_t(addr.sa_len), &ipBuf, socklen_t(ipBuf.count), nil, 0, NI_NUMERICHOST)
            getnameinfo(&mask, socklen_t(mask.sa_len), &nmBuf, socklen_t(nmBuf.count), nil, 0, NI_NUMERICHOST)
            let ip = String(cString: ipBuf)
            let nm = String(cString: nmBuf)
            // Prefer Wi-Fi (en0) se possível
            let name = String(cString: ifa.ifa_name)
            if name == "en0" { return InterfaceInfo(ip: ip, netmask: nm) }
            best = best ?? InterfaceInfo(ip: ip, netmask: nm)
        }
        return best
    }
    
    static func cidrFromNetmask(_ mask: String) -> Int {
        let parts = mask.split(separator: ".").compactMap { UInt8($0) }
        let bits = parts.reduce(0) { $0 + $1.nonzeroBitCount }
        return bits
    }
    
    static func ipToUInt32(_ ip: String) -> UInt32? {
        var sin = in_addr()
        guard inet_aton(ip, &sin) != 0 else { return nil }
        return sin.s_addr.byteSwapped
    }
    
    static func uint32ToIP(_ val: UInt32) -> String {
        let be = val.byteSwapped
        var addr = in_addr(s_addr: be)
        let cstr = inet_ntoa(addr)
        return String(cString: cstr!)
    }
    
    static func hostsInSubnet(ip: String, cidr: Int) -> [String] {
        guard let base = ipToUInt32(ip) else { return [] }
        // Para simplicidade, varre apenas /24 se a máscara não for entre /24 e /30
        let effectiveCIDR = (cidr >= 24 && cidr <= 30) ? cidr : 24
        let hostBits = 32 - effectiveCIDR
        let netMask: UInt32 = hostBits == 32 ? 0 : ~UInt32(0) << hostBits
        let network = base & netMask
        let count = Int(1 << hostBits)
        var ips: [String] = []
        for i in 1..<(count-1) { // evita network e broadcast
            let addr = network | UInt32(i)
            ips.append(uint32ToIP(addr))
        }
        return ips
    }
    
    static func reverseDNS(ip: String) -> String? {
        var sa = sockaddr_in()
        sa.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        sa.sin_family = sa_family_t(AF_INET)
        inet_pton(AF_INET, ip, &sa.sin_addr)

        var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))

        let result: Int32 = withUnsafePointer(to: &sa) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { ptr in
                getnameinfo(ptr,
                            socklen_t(MemoryLayout<sockaddr_in>.size),
                            &hostBuffer,
                            socklen_t(hostBuffer.count),
                            nil, 0, NI_NAMEREQD)
            }
        }

        if result == 0 {
            return String(cString: hostBuffer)
        }
        return nil
    }
    
    static func run(_ cmd: String, args: [String], timeout: TimeInterval? = nil) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: cmd)
        p.arguments = args
        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        let sem = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in sem.signal() }
        do {
            try p.run()
        } catch {
            return nil
        }
        if let timeout = timeout {
            let deadline = DispatchTime.now() + timeout
            if sem.wait(timeout: deadline) == .timedOut {
                // excedeu o tempo limite — termina o processo
                p.terminate()
                _ = sem.wait(timeout: .now() + 1)
            }
        } else {
            p.waitUntilExit()
        }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
    
    static func ping(ip: String, timeoutSeconds: Double = 0.7) -> Bool {
        // macOS ping: -c 1 (uma tentativa), -W (timeout em ms por pacote), -n (não faz DNS), -q (quiet)
        // Além disso, aplicamos um timeout externo ao processo (fallback) via `run(timeout:)`.
        let waitMS = max(100, Int(timeoutSeconds * 1000))
        let result = run("/sbin/ping", args: ["-c","1","-W","\(waitMS)","-n","-q", ip], timeout: timeoutSeconds + 0.2)
        guard let result else { return false }
        // Considera vivo se houver "1 packets received" ou "1 packets transmitted, 1 received"
        return result.contains("1 packets received") || result.contains("1 packets transmitted, 1 packets received") || result.contains("1 received")
    }
    
    static func arpFor(ip: String) -> String? {
        guard let out = run("/usr/sbin/arp", args: ["-n", ip]) else { return nil }
        // Exemplo de linha: ? (192.168.1.10) at a1:b2:c3:d4:e5:f6 on en0 ifscope [ethernet]
        let parts = out.split(separator: "\n")
        for line in parts {
            if let atRange = line.range(of: " at "),
               let onRange = line.range(of: " on ") {
                let mac = line[atRange.upperBound..<onRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                if mac != "(incomplete)" { return mac }
            }
        }
        return nil
    }

    static func arpAll() -> [(ip: String, mac: String)] {
        guard let out = run("/usr/sbin/arp", args: ["-an"]) else { return [] }
        var results: [(String, String)] = []
        // Linhas típicas: ? (192.168.1.10) at a1:b2:c3:d4:e5:f6 on en0 ifscope [ethernet]
        for line in out.split(separator: "\n") {
            guard let open = line.firstIndex(of: "("),
                  let close = line.firstIndex(of: ")"),
                  let atRange = line.range(of: " at ") else { continue }
            let ip = String(line[line.index(after: open)..<close])
            let tail = line[atRange.upperBound...]
            let mac = tail.split(separator: " ").first.map(String.init) ?? ""
            if mac != "(incomplete)" && !mac.isEmpty {
                results.append((ip, mac))
            }
        }
        return results
    }
}

// MARK: - Scanner

@MainActor
final class NetworkScanner: ObservableObject {
    @Published var devices: [Device] = []
    @Published var isScanning = false
    @Published var progress: Double = 0
    @Published var status: String = "Pronto"
    
    private let networkManager = NetworkManager.shared
    private let ouiManager = OUIManager.shared
    
    func startScan() {
        guard !isScanning else { return }
        isScanning = true
        progress = 0
        status = "A obter interface…"
        devices = []
        
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            
            guard let iface = NetUtils.getPrimaryIPv4() else {
                await self.finishScan(withStatus: "Sem IPv4 ativo")
                return
            }
            let cidr = NetUtils.cidrFromNetmask(iface.netmask)
            let hosts = NetUtils.hostsInSubnet(ip: iface.ip, cidr: cidr)
            let total = hosts.count
            await self.updateStatus("A varrer \(total) IPs em \(subnetLabel(ip: iface.ip, cidr: cidr))…")
            
            var found: [Device] = []
            let concurrency = 64
            
            await withTaskGroup(of: Device?.self) { group in
                var index = 0
                // Enfileira até 'concurrency' em paralelo
                func enqueueNext(_ count: Int) {
                    for _ in 0..<count {
                        guard index < hosts.count else { return }
                        let ip = hosts[index]
                        index += 1
                        group.addTask {
                            // pequeno “nudge” ICMP
                            let alive = NetUtils.ping(ip: ip)
                            if !alive { return nil }
                            // ARP para MAC
                            let mac = NetUtils.arpFor(ip: ip)
                            // DNS reverso
                            let hn = NetUtils.reverseDNS(ip: ip)
                            var dev = Device(ip: ip, mac: mac, hostname: hn, customIconPath: nil)
                            if let mac = mac { 
                                dev.customIconPath = IconManager.shared.iconPath(forMAC: mac)
                                // Auto-fill brand from MAC
                                dev.brand = OUIManager.shared.getBrand(fromMAC: mac)
                            }
                            return dev
                        }
                    }
                }
                enqueueNext(min(concurrency, hosts.count))
                
                var processed = 0
                for await maybe in group {
                    processed += 1
                    if let d = maybe { found.append(d) }
                    await self.updateProgress(Double(processed) / Double(max(1,total)))
                    enqueueNext(1) // mantém pipeline
                }
            }
            // Fallback: incluir entradas conhecidas na ARP table (mesmo que não tenham respondido a ping)
            let arpEntries = NetUtils.arpAll()
            let presentIPs = Set(found.map { $0.ip })
            // Restringe a mesma sub-rede do scan
            let subnetCIDR = (NetUtils.cidrFromNetmask(iface.netmask) >= 24 && NetUtils.cidrFromNetmask(iface.netmask) <= 30) ? NetUtils.cidrFromNetmask(iface.netmask) : 24
            let subnetIPs = Set(NetUtils.hostsInSubnet(ip: iface.ip, cidr: subnetCIDR))
            for (ip, mac) in arpEntries {
                guard !presentIPs.contains(ip), subnetIPs.contains(ip) else { continue }
                let hn = NetUtils.reverseDNS(ip: ip)
                var dev = Device(ip: ip, mac: mac, hostname: hn, customIconPath: nil)
                dev.customIconPath = IconManager.shared.iconPath(forMAC: mac)
                dev.brand = OUIManager.shared.getBrand(fromMAC: mac)
                found.append(dev)
            }
            // Ordena por IP
            found.sort { ipLess($0.ip, $1.ip) }
            
            // Save to network persistence
            await self.saveToNetwork(devices: found)
            
            await self.applyResults(found)
            await self.finishScan(withStatus: "Concluído: \(found.count) dispositivos")
        }
    }
    
    private func saveToNetwork(devices: [Device]) async {
        // Get current SSID and save devices to that network
        let ssid = networkManager.getCurrentSSID() ?? "Desconhecida"
        await MainActor.run {
            networkManager.addOrUpdateNetwork(ssid: ssid, devices: devices)
        }
    }
    
    func stopScan() {
        // Simples: não temos cancelamento fino do ping externo — em produção, troca por ICMP nativo e usa Task cancellation.
        isScanning = false
        status = "Cancelado"
    }
    
    private func applyResults(_ list: [Device]) {
        self.devices = list
    }
    private func updateProgress(_ p: Double) {
        self.progress = p
    }
    private func updateStatus(_ s: String) {
        self.status = s
    }
    private func finishScan(withStatus s: String) {
        self.isScanning = false
        self.status = s
    }
}

// Helpers
func subnetLabel(ip: String, cidr: Int) -> String {
    "\(ip)/\( (cidr >= 24 && cidr <= 30) ? cidr : 24)"
}
func ipToSortable(_ ip: String) -> [Int] {
    ip.split(separator: ".").compactMap { Int($0) }
}

func ipLess(_ a: String, _ b: String) -> Bool {
    let aa = ipToSortable(a)
    let bb = ipToSortable(b)
    let n = max(aa.count, bb.count)
    for i in 0..<n {
        let av = i < aa.count ? aa[i] : 0
        let bv = i < bb.count ? bb[i] : 0
        if av != bv { return av < bv }
    }
    return false
}

// MARK: - Views

struct ContentView: View {
    @StateObject private var scanner = NetworkScanner()
    @StateObject private var networkManager = NetworkManager.shared
    @State private var query = ""
    @State private var showOnlyWithMAC = false
    @State private var editingNetworkId: UUID? = nil
    @State private var editingDeviceId: UUID? = nil
    
    var filtered: [Device] {
        let devices = networkManager.getDevicesForSelectedNetwork()
        return devices.filter { d in
            let hay = "\(d.displayName) \(d.ip) \(d.mac ?? "") \(d.owner) \(d.brand) \(d.model)".lowercased()
            let ok = query.isEmpty || hay.contains(query.lowercased())
            return ok && (!showOnlyWithMAC || d.mac != nil)
        }
    }
    
    var body: some View {
        NavigationSplitView {
            // Sidebar with networks
            networksSidebar
        } detail: {
            // Main content with devices
            if networkManager.selectedNetworkId != nil {
                deviceListView
                    .id(networkManager.selectedNetworkId) // Refresh when network changes
            } else {
                VStack {
                    Text("Selecione uma rede")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Escolha uma rede na barra lateral para ver os dispositivos")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .onAppear {
            // Auto-select first network if available
            if networkManager.selectedNetworkId == nil,
               let firstNetwork = networkManager.networks.first {
                networkManager.selectedNetworkId = firstNetwork.id
            }
        }
    }
    
    private var networksSidebar: some View {
        VStack(spacing: 0) {
            // Sidebar header
            HStack {
                Text("Redes Wi-Fi")
                    .font(.headline)
                Spacer()
                Button {
                    scanner.startScan()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(scanner.isScanning)
            }
            .padding()
            
            // Networks list
            List(networkManager.networks, selection: $networkManager.selectedNetworkId) { network in
                NetworkRow(network: network) { emoji in
                    networkManager.updateNetworkEmoji(network.id, emoji: emoji)
                }
            }
            .listStyle(.sidebar)
            
            if scanner.isScanning {
                VStack(spacing: 4) {
                    ProgressView(value: scanner.progress)
                    Text(scanner.status)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .frame(minWidth: 200)
    }
    
    private var deviceListView: some View {
        VStack(spacing: 0) {
            toolbar
            devicesList
            footer
        }
    }
    
    private var toolbar: some View {
        HStack {
            TextField("Pesquisar dispositivos…", text: $query)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(maxWidth: 320)
            Toggle("Só com MAC", isOn: $showOnlyWithMAC)
                .toggleStyle(.switch)
            Spacer()
            Button {
                scanner.startScan()
            } label: {
                Label("Scan", systemImage: "dot.radiowaves.left.and.right")
            }
            .disabled(scanner.isScanning)
            Button(role: .destructive) {
                scanner.stopScan()
            } label: {
                Label("Parar", systemImage: "stop.circle")
            }
            .disabled(!scanner.isScanning)
        }
        .padding()
    }
    
    private var devicesList: some View {
        List {
            Section(header: devicesHeaderRow) {
                ForEach(filtered) { device in
                    DeviceRow(
                        device: device,
                        isEditing: editingDeviceId == device.id,
                        onEdit: { editingDeviceId = device.id },
                        onSave: { updatedDevice in
                            if let networkId = networkManager.selectedNetworkId {
                                networkManager.updateDevice(updatedDevice, in: networkId)
                            }
                            editingDeviceId = nil
                        },
                        onCancel: { editingDeviceId = nil },
                        onDropPNG: { droppedURL in
                            if let mac = device.mac {
                                IconManager.shared.setIcon(forMAC: mac, imageURL: droppedURL)
                                refreshIcon(forMAC: mac)
                            }
                        },
                        onClearIcon: {
                            if let mac = device.mac {
                                IconManager.shared.removeIcon(forMAC: mac)
                                refreshIcon(forMAC: mac)
                            }
                        }
                    )
                }
            }
        }
        .listStyle(.inset)
    }
    
    private var footer: some View {
        HStack {
            Button {
                exportCSV(devices: filtered)
            } label: {
                Label("Exportar CSV", systemImage: "square.and.arrow.down")
            }
            Spacer()
            if let network = networkManager.getSelectedNetwork() {
                Text("\(filtered.count) dispositivos em \(network.ssid)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding([.horizontal, .bottom])
    }
    
    private var devicesHeaderRow: some View {
        HStack(spacing: 12) {
            Text("Ícone").frame(width: 60, alignment: .leading)
            Text("Hostname / IP").frame(width: 140, alignment: .leading)
            Text("MAC").frame(width: 140, alignment: .leading)
            Text("Dono").frame(width: 100, alignment: .leading)
            Text("Marca").frame(width: 80, alignment: .leading)
            Text("Modelo").frame(width: 100, alignment: .leading)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.leading, 8)
    }
    
    private func refreshIcon(forMAC mac: String) {
        // Refresh the network manager to show updated icons
        if let networkId = networkManager.selectedNetworkId,
           let networkIndex = networkManager.networks.firstIndex(where: { $0.id == networkId }) {
            for (deviceMAC, device) in networkManager.networks[networkIndex].devices {
                if deviceMAC.uppercased() == mac.uppercased() {
                    var updatedDevice = device
                    updatedDevice.customIconPath = IconManager.shared.iconPath(forMAC: mac)
                    networkManager.networks[networkIndex].devices[deviceMAC] = updatedDevice
                }
            }
        }
    }
    
    private func exportCSV(devices: [Device]) {
        let header = "ip,mac,hostname,owner,brand,model\n"
        let rows = devices.map { 
            "\"\($0.ip)\",\"\($0.mac ?? "")\",\"\($0.hostname ?? "")\",\"\($0.owner)\",\"\($0.brand)\",\"\($0.model)\"" 
        }.joined(separator: "\n")
        let csv = header + rows + "\n"
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "devices.csv"
        panel.begin { resp in
            if resp == .OK, let url = panel.url {
                try? csv.data(using: .utf8)?.write(to: url)
            }
        }
    }
}

struct NetworkRow: View {
    let network: WiFiNetwork
    var onEmojiUpdate: (String) -> Void
    @State private var isEditingEmoji = false
    @State private var newEmoji = ""
    
    var body: some View {
        HStack(spacing: 8) {
            // Emoji button
            Button {
                newEmoji = network.emoji
                isEditingEmoji = true
            } label: {
                Text(network.emoji)
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .alert("Editar Emoji", isPresented: $isEditingEmoji) {
                TextField("Emoji", text: $newEmoji)
                Button("Cancelar", role: .cancel) { }
                Button("Salvar") {
                    if !newEmoji.isEmpty {
                        onEmojiUpdate(newEmoji)
                    }
                }
            } message: {
                Text("Digite um emoji para esta rede")
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(network.ssid)
                    .font(.subheadline)
                    .lineLimit(1)
                Text("\(network.deviceCount) dispositivos")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .contentShape(Rectangle())
    }
}

struct DeviceRow: View {
    let device: Device
    let isEditing: Bool
    var onEdit: () -> Void
    var onSave: (Device) -> Void
    var onCancel: () -> Void
    var onDropPNG: (URL) -> Void
    var onClearIcon: () -> Void
    
    @State private var editedDevice: Device
    
    init(device: Device, isEditing: Bool, onEdit: @escaping () -> Void, onSave: @escaping (Device) -> Void, onCancel: @escaping () -> Void, onDropPNG: @escaping (URL) -> Void, onClearIcon: @escaping () -> Void) {
        self.device = device
        self.isEditing = isEditing
        self.onEdit = onEdit
        self.onSave = onSave
        self.onCancel = onCancel
        self.onDropPNG = onDropPNG
        self.onClearIcon = onClearIcon
        self._editedDevice = State(initialValue: device)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            iconView
                .frame(width: 48, height: 48)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
                .help(device.mac != nil ? "Clique com botão direito para carregar imagem personalizada ou arraste uma imagem PNG" : "Dispositivo sem MAC")
            
            // Hostname / IP
            VStack(alignment: .leading, spacing: 2) {
                Text(device.displayName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(device.ip)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 140, alignment: .leading)
            
            // MAC
            Text(device.mac ?? "–")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(device.mac == nil ? .secondary : .primary)
                .frame(width: 140, alignment: .leading)
            
            // Owner (editable)
            if isEditing {
                TextField("Dono", text: $editedDevice.owner)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
            } else {
                Text(device.owner.isEmpty ? "–" : device.owner)
                    .font(.caption)
                    .foregroundStyle(device.owner.isEmpty ? .secondary : .primary)
                    .frame(width: 100, alignment: .leading)
                    .onTapGesture { onEdit() }
            }
            
            // Brand (editable)
            if isEditing {
                TextField("Marca", text: $editedDevice.brand)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
            } else {
                Text(device.brand.isEmpty ? "–" : device.brand)
                    .font(.caption)
                    .foregroundStyle(device.brand.isEmpty ? .secondary : .primary)
                    .frame(width: 80, alignment: .leading)
                    .onTapGesture { onEdit() }
            }
            
            // Model (editable)
            if isEditing {
                TextField("Modelo", text: $editedDevice.model)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
            } else {
                Text(device.model.isEmpty ? "–" : device.model)
                    .font(.caption)
                    .foregroundStyle(device.model.isEmpty ? .secondary : .primary)
                    .frame(width: 100, alignment: .leading)
                    .onTapGesture { onEdit() }
            }
            
            // Edit buttons
            if isEditing {
                HStack(spacing: 4) {
                    Button("✓") {
                        onSave(editedDevice)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.green)
                    
                    Button("✕") {
                        editedDevice = device
                        onCancel()
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                }
            }
        }
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for prov in providers {
                _ = prov.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.pathExtension.lowercased() == "png" else { return }
                    onDropPNG(url)
                }
            }
            return true
        }
        .contextMenu {
            if !isEditing {
                Button("Editar", action: onEdit)
            }
            if device.mac != nil {
                Button("Carregar imagem...") {
                    loadCustomIcon()
                }
                Button("Remover ícone personalizado", action: onClearIcon)
            }
        }
        .onChange(of: device) { _, newDevice in
            if !isEditing {
                editedDevice = newDevice
            }
        }
    }
    
    @ViewBuilder
    private var iconView: some View {
        if let path = device.customIconPath,
           let nsimg = NSImage(contentsOfFile: path) {
            Image(nsImage: nsimg)
                .resizable()
                .scaledToFit()
                .padding(4)
        } else {
            Text(device.iconEmoji)
                .font(.system(size: 24))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    private func loadCustomIcon() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.png]
        panel.title = "Selecionar imagem PNG"
        panel.prompt = "Escolher"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                onDropPNG(url)
            }
        }
    }
}

// MARK: - App

@main
struct NetScanApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.expanded)
    }
}
