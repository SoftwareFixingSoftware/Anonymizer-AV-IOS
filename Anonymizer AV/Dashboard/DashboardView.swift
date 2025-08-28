// DashboardView.swift
// Live dashboard: battery / CPU / memory (approximate)
// Includes batteryDisplayText, sparklines, and 2s poll interval
//

import SwiftUI
import Charts
import Darwin

struct DashboardView: View {
    @Binding var selectedTab: Int

    @State private var lastScan: String = "No scans yet"
    @State private var threatsFound: Int = 0

    // live metrics (current values)
    @State private var batteryPercent: Double = 0
    @State private var cpuPercent: Double = 0
    @State private var memoryPercent: Double = 0

    // history for sparklines
    @State private var batteryHistory: [Double] = []
    @State private var cpuHistory: [Double] = []
    @State private var memoryHistory: [Double] = []
    private let historyMax = 30

    // smoothing for CPU so UI remains pleasant
    @State private var cpuEMA: Double = 0
    private let cpuSmoothingAlpha: Double = 0.18

    @State private var path: [String] = []

    // polling (2s default)
    private let pollIntervalSeconds: TimeInterval = 2.0
    @State private var pollTask: Task<Void, Never>? = nil

    private let coreFeatures: [Feature] = [
        Feature(iconName: "exclamationmark.shield.fill", title: "Breach Scan", description: "Assure your Data"),
        Feature(iconName: "qrcode.viewfinder", title: "QR Code", description: "Clean scan"),
        Feature(iconName: "clock.fill", title: "Scan History", description: "Previous scans")
    ]

    private let securityAndTools: [Feature] = [
        Feature(iconName: "globe", title: "Secure Browser", description: "Private browsing"),
        Feature(iconName: "wifi", title: "Wifi", description: "Check traffic"),
        Feature(iconName: "speedometer", title: "Optimization", description: "Clean Duplicates"),
    ]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    QuarantineCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(lastScan)
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text("Threats found: \(threatsFound)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }

                    Button(action: { selectedTab = 1 }) {
                        Text("Scan Now")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)

                    SectionHeader(title: "Core Features")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(coreFeatures) { feature in
                                QuarantineCard {
                                    FeatureCard(feature: feature) {
                                        handleFeatureTap(feature)
                                    }
                                    .frame(height: 130)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }

                    SectionHeader(title: "Security & Tools")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(securityAndTools) { feature in
                                QuarantineCard {
                                    FeatureCard(feature: feature) {
                                        handleFeatureTap(feature)
                                    }
                                    .frame(height: 130)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }

                    SectionHeader(title: "Performance (Live)")
                    QuarantineCard {
                        VStack(spacing: 12) {
                            // Big overview chart (bars)
                            Chart {
                                BarMark(x: .value("Metric", "Battery"), y: .value("Percent", batteryPercent))
                                    .annotation(position: .top) { Text(batteryDisplayText) }
                                BarMark(x: .value("Metric", "CPU"), y: .value("Percent", cpuPercent))
                                    .annotation(position: .top) { Text("\(Int(cpuPercent))%") }
                                BarMark(x: .value("Metric", "Memory"), y: .value("Percent", memoryPercent))
                                    .annotation(position: .top) { Text("\(Int(memoryPercent))%") }
                            }
                            .chartYAxis { AxisMarks(position: .leading, values: .stride(by: 10)) }
                            .frame(height: 160)
                            .padding(.horizontal, 6)

                            // Sparklines row
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Battery")
                                        .font(.caption)
                                    SparklineChart(data: batteryHistory)
                                        .frame(height: 50)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("CPU")
                                        .font(.caption)
                                    SparklineChart(data: cpuHistory)
                                        .frame(height: 50)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Memory")
                                        .font(.caption)
                                    SparklineChart(data: memoryHistory)
                                        .frame(height: 50)
                                }
                            }
                        }
                        .padding()
                    }

                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .onAppear {
                loadLastScan()
                startPolling()
            }
            .onDisappear {
                stopPolling()
            }
            .navigationDestination(for: String.self) { route in
                switch route {
                case "history": HistoryView()
                case "breach": BreachScanView()
                case "browser": SecureBrowserView()
                case "Wifi": WifiSecurityView()
                case "qr": QrScannerView()
                case "Optimization": Optimization()
                default: EmptyView()
                }
            }
        }
    }

    // MARK: - battery text (shows N/A if unknown)
    private var batteryDisplayText: String {
        let level = UIDevice.current.batteryLevel
        if level < 0 { return "N/A" }
        return "\(Int(batteryPercent))%"
    }

    // MARK: - Polling control (2s interval)
    private func startPolling() {
        // Ensure battery monitoring is enabled on the main actor before sampling.
        Task { @MainActor in
            UIDevice.current.isBatteryMonitoringEnabled = true
            // seed with initial battery value if available
            let level = UIDevice.current.batteryLevel
            if level >= 0 { batteryPercent = Double(level * 100.0) }
        }

        // single Task loop for metrics
        pollTask = Task {
            while !Task.isCancelled {
                // Read battery on main actor so the system gives a valid reading
                var battValue: Double = batteryPercent
                await MainActor.run {
                    let level = UIDevice.current.batteryLevel
                    if level >= 0 {
                        battValue = Double(level * 100.0)
                    }
                    // keep previous if unknown
                }

                // sample system metrics (off main to avoid blocking UI)
                let mem = SystemMetrics.currentMemoryPercent()
                let cpuSample = SystemMetrics.currentCPUPercent()

                // apply EMA to CPU
                let newCpu = cpuEMA == 0 ? cpuSample : (cpuSmoothingAlpha * cpuSample + (1 - cpuSmoothingAlpha) * cpuEMA)
                cpuEMA = newCpu

                // update history and current values on main actor
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        batteryPercent = battValue
                        memoryPercent = mem
                        cpuPercent = cpuEMA
                    }

                    append(&batteryHistory, value: batteryPercent)
                    append(&cpuHistory, value: cpuPercent)
                    append(&memoryHistory, value: memoryPercent)
                }

                try? await Task.sleep(nanoseconds: UInt64(pollIntervalSeconds * 1_000_000_000))
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        Task { @MainActor in
            UIDevice.current.isBatteryMonitoringEnabled = false
        }
    }

    private func append(_ arr: inout [Double], value: Double) {
        arr.append(value)
        if arr.count > historyMax { arr.removeFirst(arr.count - historyMax) }
    }

    // MARK: - other helpers (unchanged)
    private func handleFeatureTap(_ feature: Feature) {
        switch feature.title {
        case "Deep Scan":
            selectedTab = 1
        case "Scan History":
            path.append("history")
        case "Breach Scan":
            path.append("breach")
        case "Secure Browser":
            path.append("browser")
        case "Wifi":
            path.append("Wifi")
        case "QR Code":
            path.append("qr")
        case "Optimization":
            path.append("Optimization")
        default:
            print("\(feature.title) tapped")
        }
    }

    private func loadLastScan() {
        let logs = ScanLogManager.getLogs()
        // We'll accept multiple separators and multiple date formats.
        var datedLogs: [(Date, String)] = []

        for log in logs {
            let trimmed = log.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            // Try to split into date part and details using a set of separators
            if let (dateStr, details) = splitLogEntry(trimmed) {
                if let date = parseDate(from: dateStr) {
                    datedLogs.append((date, details))
                } else {
                    // couldn't parse date — try to log for debugging and skip
                    print("DashboardView.loadLastScan: failed to parse date '\(dateStr)' in log: '\(trimmed)'")
                }
            } else {
                // Fallback: try to parse the first N characters as a timestamp (common fixed-length)
                // e.g. "2025-08-29 12:34:56 rest..."
                let prefixLen = min(19, trimmed.count)
                let prefix = String(trimmed.prefix(prefixLen))
                if let date = parseDate(from: prefix) {
                    let details = trimmed.dropFirst(prefixLen).trimmingCharacters(in: .whitespacesAndNewlines)
                    datedLogs.append((date, details))
                } else {
                    print("DashboardView.loadLastScan: could not split log entry: '\(trimmed)'")
                }
            }
        }

        if let latest = datedLogs.sorted(by: { $0.0 < $1.0 }).last {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            displayFormatter.timeStyle = .short
            lastScan = "Last scan: \(displayFormatter.string(from: latest.0))"
            threatsFound = extractThreats(from: latest.1)
        } else {
            lastScan = "No scans yet"
            threatsFound = 0
        }
    }

    /// Try several separators and return (dateString, details) if any match.
    private func splitLogEntry(_ log: String) -> (String, String)? {
        let separators = [" — ", " - ", "—", " - ", "|"]
        for sep in separators {
            if let range = log.range(of: sep) {
                let d = String(log[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let details = String(log[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                return (d, details)
            }
        }
        return nil
    }

    /// Parse date from a string using several common formats; fallback to ISO8601.
    private func parseDate(from s: String) -> Date? {
        let formats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd HH:mm:ss Z"
        ]

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        for f in formats {
            formatter.dateFormat = f
            if let d = formatter.date(from: s) { return d }
        }

        // try ISO8601 fallback
        if #available(iOS 10.0, *) {
            let iso = ISO8601DateFormatter()
            if let d = iso.date(from: s) { return d }
        }

        return nil
    }

    private func extractThreats(from details: String) -> Int {
        // Look for common patterns like:
        // "3 threats", "3 threat", "threats: 3", "threat: 3", "Found 3 threats", etc.
        let lower = details.lowercased()

        // 1) Try regex: number before the word (e.g. "3 threats")
        if let n = firstMatchNumber(pattern: "(?i)(\\d+)\\s*(?:threats?|threat)\\b", in: lower) {
            return n
        }

        // 2) Try regex: number after the word (e.g. "threats: 3")
        if let n2 = firstMatchNumber(pattern: "(?i)(?:threats?|threat)\\D{0,8}(\\d+)", in: lower) {
            return n2
        }

        // 3) Fallback: try to find any integer in the details that appears near the word 'threat'
        if let idx = lower.range(of: "threat") {
            // take 20 chars window before the match and try to capture a number
            let start = lower.startIndex
            let preWindowStart = lower.index(idx.lowerBound, offsetBy: -20, limitedBy: start) ?? start
            let window = String(lower[preWindowStart..<idx.upperBound])
            if let n3 = firstMatchNumber(pattern: "(\\d+)", in: window) {
                return n3
            }
        }

        // nothing found
        return 0
    }

    private func firstMatchNumber(pattern: String, in text: String) -> Int? {
        do {
            let re = try NSRegularExpression(pattern: pattern, options: [])
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if let m = re.firstMatch(in: text, options: [], range: range) {
                if m.numberOfRanges >= 2, let r = Range(m.range(at: 1), in: text) {
                    let substr = String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                    return Int(substr)
                }
            }
        } catch {
            print("DashboardView.firstMatchNumber: regex error: \(error)")
        }
        return nil
    }
}

// MARK: - Sparkline subview (simple lightweight)
struct SparklineChart: View {
    let data: [Double]

    var body: some View {
        if data.isEmpty {
            Rectangle()
                .fill(Color(UIColor.systemGray5))
                .cornerRadius(6)
        } else {
            Chart {
                ForEach(Array(data.enumerated()), id: \.offset) { idx, val in
                    LineMark(x: .value("idx", idx), y: .value("val", val))
                        .interpolationMethod(.monotone)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

// MARK: - SystemMetrics: CPU & Memory helpers (fixed)
enum SystemMetrics {
    static func currentMemoryPercent() -> Double {
        var size: mach_msg_type_number_t = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var vmstat = vm_statistics64()
        let hostPort: host_t = mach_host_self()
        let result = withUnsafeMutablePointer(to: &vmstat) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &size)
            }
        }
        if result != KERN_SUCCESS { return 0.0 }
        var pageSize: vm_size_t = 0
        host_page_size(hostPort, &pageSize)

        let free = Double(vmstat.free_count) * Double(pageSize)
        let active = Double(vmstat.active_count) * Double(pageSize)
        let inactive = Double(vmstat.inactive_count) * Double(pageSize)
        let wired = Double(vmstat.wire_count) * Double(pageSize)
        let compressed = Double(vmstat.compressor_page_count) * Double(pageSize)

        let used = active + inactive + wired + compressed
        let total = used + free
        if total <= 0 { return 0.0 }
        return (used / total) * 100.0
    }

    /// Approximate system CPU percent (snapshot) — fixed index math and safe deallocation.
    static func currentCPUPercent() -> Double {
        var numProcessorsU: natural_t = 0
        var cpuInfoPtr: processor_info_array_t? = nil
        var numCpuInfo: mach_msg_type_number_t = 0

        let kr = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numProcessorsU, &cpuInfoPtr, &numCpuInfo)
        guard kr == KERN_SUCCESS, let cpuInfo = cpuInfoPtr else {
            return 0.0
        }

        let nCPUs = Int(numProcessorsU)
        var totalUsage: Double = 0.0

        // Cast C constants to Int for safe indexing
        let cpuStateMax = Int(CPU_STATE_MAX)
        let cpuUser = Int(CPU_STATE_USER)
        let cpuSystem = Int(CPU_STATE_SYSTEM)
        let cpuNice = Int(CPU_STATE_NICE)
        let cpuIdle = Int(CPU_STATE_IDLE)

        for cpuIndex in 0..<nCPUs {
            let base = cpuStateMax * cpuIndex
            let user = Double(cpuInfo[base + cpuUser])
            let system = Double(cpuInfo[base + cpuSystem])
            let nice = Double(cpuInfo[base + cpuNice])
            let idle = Double(cpuInfo[base + cpuIdle])
            let sum = user + system + nice + idle
            if sum > 0 {
                let usage = (user + system + nice) / sum
                totalUsage += usage
            }
        }

        // deallocate buffer returned by host_processor_info
        let cpuInfoSize = Int(numCpuInfo) * MemoryLayout<integer_t>.size
        let addr = vm_address_t(bitPattern: cpuInfo)
        vm_deallocate(mach_task_self_, addr, vm_size_t(cpuInfoSize))

        if nCPUs == 0 { return 0.0 }
        return (totalUsage / Double(nCPUs)) * 100.0
    }
}

// MARK: - Section Header and Card (same as original)
struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundColor(.primary)
            .padding(.horizontal)
    }
}

struct QuarantineCard<Content: View>: View {
    let content: () -> Content
    var body: some View {
        VStack { content() }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.18), lineWidth: 0.5)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)))
            )
            .padding(.horizontal)
    }
}
