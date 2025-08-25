//
//  ScanSession.swift
//  Anonymizer AV
//
//  Central scan state & progress tracking
//

import SwiftUI
import CryptoKit

@MainActor
class ScanSession: ObservableObject {
    // selection + results
    @Published var selectedFiles: [URL] = []
    @Published var threats: [String] = []
    @Published var consoleLines: [String] = ["Ready"]

    // scan state
    @Published var isScanning = false
    @Published var isFinished = false
    @Published var currentFile: String = ""
    /// Fractional progress 0.0 ... 1.0 (suitable for ProgressView(value:))
    @Published var progressFraction: Double = 0.0
    /// Optional raw count-based progress if you prefer (files scanned)
    @Published var progressCount: Int = 0

    // Navigation flags (views use these)
    @Published var showProgress = false
    @Published var showResults = false

    // internal scan task (cancellable)
    private var scanTask: Task<Void, Never>?

    // MARK: - public API

    /// Start scanning the provided files. Cancels any previous scan.
    func startScan(with files: [URL]) {
        // cancel previous
        scanTask?.cancel()
        scanTask = nil

        // init state
        selectedFiles = files
        threats = []
        consoleLines = ["Initializing scan..."]
        isScanning = true
        isFinished = false
        currentFile = ""
        progressFraction = 0.0
        progressCount = 0
        showProgress = true
        showResults = false

        // Launch detached task to do background work
        scanTask = Task.detached { [weak self] in
            guard let self = self else { return }
            let total = files.count

            // Ensure signatures are loaded BEFORE scanning begins
            await MainActor.run {
                self.logConsole("Loading signature database...")
                SignatureScanner.loadSignatures()
                self.logConsole("Signature load requested.")
            }

            for (index, file) in files.enumerated() {
                if Task.isCancelled { break }

                // update UI about current file
                await MainActor.run {
                    self.currentFile = file.lastPathComponent
                    self.progressCount = index
                    self.progressFraction = total > 0 ? Double(index) / Double(total) : 0.0
                    ScanningLogger.shared.logFileScanStart(file)
                }

                // Hash file off-main
                var digestHex: String? = nil
                var fileSize = 0
                do {
                    let data = try Data(contentsOf: file)
                    let digest = Insecure.MD5.hash(data: data)
                    digestHex = digest.map { String(format: "%02hhx", $0) }.joined()
                    fileSize = data.count
                } catch {
                    await MainActor.run {
                        ScanningLogger.shared.logScanError(file, error: error)
                        self.logConsole("[ERROR] Failed to hash \(file.lastPathComponent): \(error.localizedDescription)")
                    }
                }

                if let md5 = digestHex {
                    await MainActor.run {
                        self.logConsole("[scan] calling SignatureScanner for \(file.lastPathComponent) md5=\(md5)")
                    }

                    let threat: String? = await MainActor.run {
                        SignatureScanner.scanHash(md5Hex: md5, size: fileSize)
                    }

                    await MainActor.run {
                        self.logConsole("[scan] SignatureScanner returned: \(String(describing: threat)) for \(file.lastPathComponent)")
                    }

                    if let threat = threat {
                        let threatLine = "\(file.path) → \(threat)"
                        await MainActor.run {
                            self.threats.append(threatLine)
                            self.logConsole("[THREAT] \(file.lastPathComponent) → \(threat)")
                            ScanningLogger.shared.logThreatDetected(file, threatName: threat)
                        }
                    } else {
                        await MainActor.run {
                            self.logConsole("[CLEAN] \(file.lastPathComponent)")
                            ScanningLogger.shared.logFileClean(file)
                        }
                    }
                }

                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms yield

                await MainActor.run {
                    self.progressCount = index + 1
                    self.progressFraction = total > 0 ? Double(index + 1) / Double(total) : 1.0
                }

                // If last file, finalize
                if index + 1 == total {
                    await MainActor.run {
                        self.logConsole("Scan completed. Scanned \(total) files.")
                        ScanningLogger.shared.logScanComplete(totalFiles: total, threatsFound: self.threats.count)
                        self.finishScan()
                    }
                }
            }

            // If task was cancelled externally, clear flags
            await MainActor.run {
                if Task.isCancelled {
                    self.logConsole("Scan cancelled.")
                    self.isScanning = false
                    self.isFinished = false
                    self.progressFraction = 0.0
                    self.currentFile = ""
                    self.showProgress = false
                    self.showResults = false
                }
            }
        }
    }

    func finishScan() {
        isScanning = false
        isFinished = true
        showResults = true

        //  Log a persistent history entry
        let summary = "Scanned \(progressCount) files, Threats: \(threats.count)"
        logConsole(summary)
        let entry = ScanLogManager.makeLogEntry(details: summary)
        ScanLogManager.saveLog(entry)
    }

    /// Cancel an in-progress scan and return to options.
    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil

        isScanning = false
        isFinished = false
        progressFraction = 0.0
        progressCount = 0
        currentFile = ""
        showProgress = false
        showResults = false

        logConsole("Scan cancelled by user.")
    }

    /// Full reset: clear everything and navigation
    func reset() {
        scanTask?.cancel()
        scanTask = nil

        isScanning = false
        isFinished = false
        selectedFiles = []
        threats = []
        consoleLines = ["Ready"]
        progressFraction = 0.0
        progressCount = 0
        currentFile = ""
        showProgress = false
        showResults = false

        logConsole("Session reset.")
    }

    // MARK: - helpers

    private func logConsole(_ msg: String) {
        if consoleLines.last != msg {
            consoleLines.append(msg)
            if consoleLines.count > 200 {
                consoleLines.removeFirst(consoleLines.count - 200)
            }
        }
        print(msg)
    }
}
