//
//  HistoryView.swift
//  Anonymizer AV
//
//  Full SwiftUI history screen that reads from ScanLogManager,
//  parses log lines, sorts, shows details and allows sharing.
//

import SwiftUI
import UIKit

// MARK: - Model
struct ScanHistoryItem: Identifiable {
    let id = UUID()
    let scanType: String
    let rawDate: String
    let formattedDate: String
    let filesCount: Int
    let threatsCount: Int
    let duration: String
    let parsedDate: Date?
}

// MARK: - Main History View
struct HistoryView: View {
    @State private var historyItems: [ScanHistoryItem] = []
    @State private var currentSortOption: SortOption = .dateDesc
    @State private var isShowingDetails: Bool = false
    @State private var selectedItem: ScanHistoryItem?
    @State private var showingClearConfirm: Bool = false

    enum SortOption: String, CaseIterable, Identifiable {
        case dateDesc = "Date ↓"
        case dateAsc = "Date ↑"
        case threatsDesc = "Threats ↓"
        case threatsAsc = "Threats ↑"

        var id: String { rawValue }
    }

    var body: some View {
        NavigationView {
            Group {
                if historyItems.isEmpty {
                    Text("No scan history available")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(historyItems) { item in
                            HistoryCard(item: item) {
                                selectedItem = item
                                isShowingDetails = true
                            }
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(PlainListStyle())
                    .refreshable { refreshHistory() }
                }
            }
            .navigationTitle("Scan History")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    // Sort menu
                    Menu {
                        Picker("Sort by", selection: $currentSortOption) {
                            ForEach(SortOption.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }

                    // Clear button
                    Button(action: { showingClearConfirm = true }) {
                        Image(systemName: "trash")
                    }
                }
            }
            .onChange(of: currentSortOption) { _ in sortHistory() }
            .onAppear { refreshHistory() }
            .alert("Scan Results", isPresented: $isShowingDetails, presenting: selectedItem) { item in
                Button("OK", role: .cancel) {}
                Button("Share") {
                    shareScanResults(item)
                }
            } message: { item in
                Text("""
                Date: \(item.formattedDate)

                Files scanned: \(item.filesCount)
                Threats found: \(item.threatsCount)
                """)
            }
            .confirmationDialog("Clear all history?", isPresented: $showingClearConfirm, titleVisibility: .visible) {
                Button("Clear History", role: .destructive) {
                    ScanLogManager.clearLogs()
                    refreshHistory()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    // MARK: - Data Logic
    private func refreshHistory() {
        let logs = ScanLogManager.getLogs()
        // Parse on background thread
        DispatchQueue.global(qos: .userInitiated).async {
            let items = parseHistoryData(from: logs)
            DispatchQueue.main.async {
                historyItems = items
                sortHistory()
            }
        }
    }

    private func parseHistoryData(from logs: [String]) -> [ScanHistoryItem] {
        var items: [ScanHistoryItem] = []
        for log in logs {
            // Expect format: "<timestamp> — <details>"
            let comps = log.components(separatedBy: "—").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard comps.count >= 2 else { continue }
            let rawDate = comps[0]
            let details = comps[1]

            // Extract numbers
            let (filesCount, threatsCount) = extractCounts(from: details)

            // Parse date
            let parsedDate = parseDate(from: rawDate)
            let formattedDate = formatOutput(date: parsedDate) ?? rawDate

            let item = ScanHistoryItem(
                scanType: "Scan",
                rawDate: rawDate,
                formattedDate: formattedDate,
                filesCount: filesCount,
                threatsCount: threatsCount,
                duration: "N/A",
                parsedDate: parsedDate
            )
            items.append(item)
        }
        return items
    }

    // MARK: - Regex helpers
    private func extractCounts(from details: String) -> (Int, Int) {
        var files = 0
        var threats = 0

        if let filesMatch = firstMatch(in: details, pattern: #"Scanned\s+(\d+)\s+files"#) {
            files = Int(filesMatch) ?? 0
        } else if let anyInt = firstMatch(in: details, pattern: #"(\d+)\s+files"#) {
            files = Int(anyInt) ?? 0
        }

        if let threatsMatch = firstMatch(in: details, pattern: #"Threats[:\s]*?(\d+)"#) {
            threats = Int(threatsMatch) ?? 0
        } else if let anyInt = firstMatch(in: details, pattern: #"(\d+)\s+threats?"#) {
            threats = Int(anyInt) ?? 0
        }

        return (files, threats)
    }

    /// Returns the first capture group or full match. Uses case-insensitive matching by default.
    private func firstMatch(in text: String, pattern: String, options: NSRegularExpression.Options = [.caseInsensitive]) -> String? {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: options)
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, options: [], range: nsRange) else { return nil }

            // prefer capture group 1 if present
            if match.numberOfRanges >= 2 {
                let range = match.range(at: 1)
                if range.location != NSNotFound, let swiftRange = Range(range, in: text) {
                    return String(text[swiftRange])
                }
            }

            // fallback to whole match
            let range = match.range(at: 0)
            if range.location != NSNotFound, let swiftRange = Range(range, in: text) {
                return String(text[swiftRange])
            }
        } catch {
            print("Regex error: \(error)")
        }
        return nil
    }

    // MARK: - Date parsing & formatting
    private func parseDate(from raw: String) -> Date? {
        let fmts: [String] = [
            "yyyy-MM-dd HH:mm:ss",    // primary (ScanLogManager.makeLogEntry)
            "MMM dd, yyyy hh:mm:ss a",
            "MMM dd, yyyy hh:mm a",
            "MMM dd, yyyy HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd"
        ]

        let locale = Locale.current
        for format in fmts {
            let df = DateFormatter()
            df.locale = locale
            df.dateFormat = format
            if let d = df.date(from: raw) { return d }
        }

        // Try flexible DateFormatter (localized)
        let flexible = DateFormatter()
        flexible.locale = locale
        flexible.dateStyle = .medium
        flexible.timeStyle = .medium
        if let d = flexible.date(from: raw) { return d }

        return nil
    }

    private func formatOutput(date: Date?) -> String? {
        guard let d = date else { return nil }
        let out = DateFormatter()
        out.locale = Locale.current
        out.dateFormat = "MMM dd, yyyy 'at' hh:mm a"
        return out.string(from: d)
    }

    // MARK: - Sorting
    private func sortHistory() {
        switch currentSortOption {
        case .dateDesc:
            historyItems.sort { ($0.parsedDate ?? Date.distantPast) > ($1.parsedDate ?? Date.distantPast) }
        case .dateAsc:
            historyItems.sort { ($0.parsedDate ?? Date.distantPast) < ($1.parsedDate ?? Date.distantPast) }
        case .threatsDesc:
            historyItems.sort { $0.threatsCount > $1.threatsCount }
        case .threatsAsc:
            historyItems.sort { $0.threatsCount < $1.threatsCount }
        }
    }

    // MARK: - Share
    private func shareScanResults(_ item: ScanHistoryItem) {
        let shareText = """
        Scan results:
        Date: \(item.formattedDate)
        Files scanned: \(item.filesCount)
        Threats found: \(item.threatsCount)
        """
        let av = UIActivityViewController(activityItems: [shareText], applicationActivities: nil)

        DispatchQueue.main.async {
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let root = scene.windows.first?.rootViewController {
                root.present(av, animated: true, completion: nil)
            } else {
                // Fallback: use keyWindow
                UIApplication.shared.windows.first?.rootViewController?.present(av, animated: true, completion: nil)
            }
        }
    }
}

// MARK: - History Card (item view)
struct HistoryCard: View {
    let item: ScanHistoryItem
    let onDetails: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(item.scanType)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()
                if item.threatsCount > 0 {
                    Text("\(item.threatsCount) threat\(item.threatsCount > 1 ? "s" : "")")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.2))
                        .foregroundColor(.red)
                        .clipShape(Capsule())
                }
            }

            Text(item.formattedDate)
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack {
                Label("\(item.filesCount) file\(item.filesCount != 1 ? "s" : "")", systemImage: "doc")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Details", action: onDetails)
                    .font(.footnote)
                    .foregroundColor(.blue)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)))
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

// MARK: - Preview
struct HistoryView_Previews: PreviewProvider {
    static var previews: some View {
        // Insert some sample data into UserDefaults so preview can show items
        let demo1 = ScanLogManager.makeLogEntry(date: Date(), details: "Scanned 120 files, Threats: 3")
        let demo2 = ScanLogManager.makeLogEntry(date: Date().addingTimeInterval(-86400), details: "Scanned 200 files, Threats: 0")
        UserDefaults.standard.set([demo1, demo2], forKey: "scan_logs")

        return HistoryView()
    }
}
