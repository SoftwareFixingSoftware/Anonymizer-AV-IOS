// ScanLogManager.swift
// Anonymizer AV
//
// Simple persistence for scan logs backed by UserDefaults.
// Stores logs as ordered array (no duplicates) and emits stable timestamps
// formatted with en_US_POSIX so parsing is reliable across locales.

import Foundation

struct ScanLogManager {
    private static let prefKey = "scan_logs"
    /// Maximum number of log entries to keep. Oldest entries are dropped when this is exceeded.
    private static let maxLogs = 500

    /// Append one line (timestamp — summary) to the saved logs.
    /// Preserves insertion order and avoids exact duplicates.
    static func saveLog(_ entry: String) {
        var current = getLogs() // ordered array
        if current.contains(entry) {
            // already recorded — keep existing order
            return
        }
        current.append(entry)

        // enforce max size
        if current.count > maxLogs {
            current = Array(current.suffix(maxLogs))
        }

        UserDefaults.standard.set(current, forKey: prefKey)
    }

    /// Return all saved log-lines in insertion order (oldest first).
    static func getLogs() -> [String] {
        return UserDefaults.standard.stringArray(forKey: prefKey) ?? []
    }

    /// Return logs parsed and sorted by Date ascending (oldest first).
    /// Lines that cannot be parsed are excluded.
    static func getLogsSortedParsed() -> [(date: Date, details: String)] {
        let logs = getLogs()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var arr: [(Date, String)] = []
        for log in logs {
            let trimmed = log.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            // split by em-dash " — " (fallbacks handled by DashboardView when needed)
            if let range = trimmed.range(of: " — ") {
                let dateStr = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let details = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if let d = formatter.date(from: dateStr) {
                    arr.append((d, details))
                }
            }
        }
        return arr.sorted(by: { $0.0 < $1.0 })
    }

    /// Remove all logs
    static func clearLogs() {
        UserDefaults.standard.removeObject(forKey: prefKey)
    }

    /// Helper to produce a timestamped log entry.
    /// Format chosen: "yyyy-MM-dd HH:mm:ss — details"
    /// Uses en_US_POSIX so the timestamp is stable and parseable.
    static func makeLogEntry(date: Date = Date(), details: String) -> String {
        let fmt = DateFormatter()
        // IMPORTANT: use en_US_POSIX for programmatic timestamps that will be parsed
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone.current
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return "\(fmt.string(from: date)) — \(details)"
    }
}
