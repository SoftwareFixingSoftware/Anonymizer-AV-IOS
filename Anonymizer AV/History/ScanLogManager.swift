//
//  ScanLogManager.swift
//  Anonymizer AV
//
//  Simple persistence for scan logs backed by UserDefaults.
//  Mirrors the Android SharedPreferences approach.
//

import Foundation

struct ScanLogManager {
    private static let prefKey = "scan_logs"

    /// Append one line (timestamp — summary) to the saved logs.
    /// Avoids exact duplicates by ensuring set semantics.
    static func saveLog(_ entry: String) {
        var current = Set(getLogs())
        current.insert(entry)
        // Save as array (UserDefaults doesn't like Set directly)
        let array = Array(current)
        UserDefaults.standard.set(array, forKey: prefKey)
    }

    /// Return all saved log-lines (unsorted)
    static func getLogs() -> [String] {
        return UserDefaults.standard.stringArray(forKey: prefKey) ?? []
    }

    /// Remove all logs
    static func clearLogs() {
        UserDefaults.standard.removeObject(forKey: prefKey)
    }

    /// Helper to produce a timestamped log entry.
    /// Format chosen is easy to parse across platforms: "yyyy-MM-dd HH:mm:ss"
    static func makeLogEntry(date: Date = Date(), details: String) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale.current
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return "\(fmt.string(from: date)) — \(details)"
    }
}
