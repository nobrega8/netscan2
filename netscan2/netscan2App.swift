import SwiftUI
import Network
import SystemConfiguration

// MARK: - Model

struct Device: Identifiable, Hashable {
    let id = UUID()
    let ip: String
    let mac: String?
    let hostname: String?
    var customIconPath: String? // PNG por MAC (se existir)
    
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
}

// MARK: - Icon Manager (por MAC)

final class IconManager {
    static let shared = IconManager()
    private let mappingKey = "iconMappingByMAC"
    private let fm = FileManager.default
    
    private init() {}
    
    private var appSupportDir: URL {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
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
    
    static func run(_ cmd: String, args: [String]) -> String? {
        let p = Process()
        p.launchPath = cmd
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do {
            try p.run()
        } catch {
            return nil
        }
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
    
    static func ping(ip: String, timeoutSeconds: Double = 1.0) -> Bool {
        // macOS ping: -c 1 (uma tentativa), -t TTL (não é timeout mas mantém rápido)
        // Vamos limitar com um watchdog assíncrono em TaskGroup; se bloquear, descartamos.
        let result = run("/sbin/ping", args: ["-c","1","-t","64", ip])
        // Considera vivo se houver "1 packets received"
        return result?.contains("1 packets received") == true || result?.contains("1 packets transmitted, 1 packets received") == true
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
}

// MARK: - Scanner

@MainActor
final class NetworkScanner: ObservableObject {
    @Published var devices: [Device] = []
    @Published var isScanning = false
    @Published var progress: Double = 0
    @Published var status: String = "Pronto"
    
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
                            if let mac = mac { dev.customIconPath = IconManager.shared.iconPath(forMAC: mac) }
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
            // Ordena por IP
            found.sort { ipLess($0.ip, $1.ip) }
            await self.applyResults(found)
            await self.finishScan(withStatus: "Concluído: \(found.count) dispositivos")
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
    @State private var query = ""
    @State private var showOnlyWithMAC = false
    
    var filtered: [Device] {
        scanner.devices.filter { d in
            let hay = "\(d.displayName) \(d.ip) \(d.mac ?? "")".lowercased()
            let ok = query.isEmpty || hay.contains(query.lowercased())
            return ok && (!showOnlyWithMAC || d.mac != nil)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            toolbar
            progressBar
            listView
            footer
        }
        .frame(minWidth: 700, minHeight: 520)
        .onAppear {
            // opcional: auto-scan à entrada
            // scanner.startScan()
        }
    }
    
    private var toolbar: some View {
        HStack {
            TextField("Pesquisar por hostname/IP/MAC…", text: $query)
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
    
    private var progressBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            if scanner.isScanning {
                ProgressView(value: scanner.progress)
            }
            Text(scanner.status)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
    
    private var listView: some View {
        List {
            Section(header: headerRow) {
                ForEach(filtered) { dev in
                    DeviceRow(device: dev) { droppedURL in
                        if let mac = dev.mac {
                            IconManager.shared.setIcon(forMAC: mac, imageURL: droppedURL)
                            refreshIcon(forMAC: mac)
                        }
                    } onClearIcon: {
                        if let mac = dev.mac {
                            IconManager.shared.removeIcon(forMAC: mac)
                            refreshIcon(forMAC: mac)
                        }
                    }
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
            Text("\(filtered.count) itens")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.trailing)
        }
        .padding([.horizontal, .bottom])
    }
    
    private var headerRow: some View {
        HStack {
            Text("Ícone").frame(width: 60, alignment: .leading)
            Text("Hostname / IP")
            Spacer()
            Text("MAC").frame(width: 200, alignment: .leading)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.leading, 8)
    }
    
    private func refreshIcon(forMAC mac: String) {
        // Atualiza a lista para refletir novo icon
        for i in scanner.devices.indices {
            if scanner.devices[i].mac?.uppercased() == mac.uppercased() {
                scanner.devices[i].customIconPath = IconManager.shared.iconPath(forMAC: mac)
            }
        }
    }
    
    private func exportCSV(devices: [Device]) {
        let header = "ip,mac,hostname\n"
        let rows = devices.map { "\"\($0.ip)\",\"\($0.mac ?? "")\",\"\($0.hostname ?? "")\"" }.joined(separator: "\n")
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

struct DeviceRow: View {
    let device: Device
    var onDropPNG: (URL) -> Void
    var onClearIcon: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            iconView
                .frame(width: 48, height: 48)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
                .padding(.vertical, 4)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(device.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Text(device.ip)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(device.mac ?? "–")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(device.mac == nil ? .secondary : .primary)
                .frame(width: 200, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            // aceita PNG
            for prov in providers {
                _ = prov.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.pathExtension.lowercased() == "png" else { return }
                    onDropPNG(url)
                }
            }
            return true
        }
        .contextMenu {
            if device.mac != nil {
                Button("Remover ícone personalizado", action: onClearIcon)
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
                .padding(6)
        } else {
            Text(device.iconEmoji)
                .font(.system(size: 28))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
