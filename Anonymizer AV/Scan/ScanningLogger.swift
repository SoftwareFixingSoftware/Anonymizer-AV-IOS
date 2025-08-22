// ------------------------------------------------------------
// ScanningLogger.swift
// Comprehensive logging for scanning operations
// ------------------------------------------------------------

import Foundation
import os.log

final class ScanningLogger {
    static let shared = ScanningLogger()
    private let log: OSLog
    
    private init() {
        log = OSLog(subsystem: "com.yourcompany.antivirus", category: "Scanning")
    }
    
    func logFileScanStart(_ fileURL: URL) {
        os_log("🟡 Starting scan: %@", log: log, type: .info, fileURL.lastPathComponent)
    }
    
    func logFileHash(_ fileURL: URL, hash: String, size: Int) {
        os_log("📊 File: %@, MD5: %@, Size: %d bytes",
               log: log, type: .info,
               fileURL.lastPathComponent, hash, size)
    }
    
    func logThreatDetected(_ fileURL: URL, threatName: String) {
        os_log("🔴 THREAT DETECTED: %@ -> %@",
               log: log, type: .error,
               fileURL.lastPathComponent, threatName)
    }
    
    func logFileClean(_ fileURL: URL) {
        os_log("✅ Clean: %@", log: log, type: .info, fileURL.lastPathComponent)
    }
    
    func logScanError(_ fileURL: URL, error: Error) {
        os_log("❌ Error scanning %@: %@",
               log: log, type: .error,
               fileURL.lastPathComponent, error.localizedDescription)
    }
    
    func logScanComplete(totalFiles: Int, threatsFound: Int) {
        os_log("🎉 Scan complete. Files: %d, Threats: %d",
               log: log, type: .info, totalFiles, threatsFound)
    }
    
    func logSignatureLoading(count: Int) {
        os_log("📋 Signatures loaded: %d entries", log: log, type: .info, count)
    }
    
    func logSignatureError(_ error: Error) {
        os_log("❌ Signature loading failed: %@", log: log, type: .error, error.localizedDescription)
    }
    
    func logNoSignaturesFound() {
        os_log("⚠️ No signature database found", log: log, type: .error)
    }
}
