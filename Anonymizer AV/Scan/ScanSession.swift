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

        // init state (on MainActor already because @MainActor for class)
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

        // Launch detached task to do background work, but keep calls to
        // signature scanning and UI updates on MainActor where necessary.
        scanTask = Task.detached { [weak self] in
            guard let self = self else { return }
            let total = files.count

            // Ensure signatures are loaded BEFORE scanning begins.
            // Run loadSignatures on the MainActor to be safe.
            await MainActor.run {
                self.logConsole("Loading signature database...")
                SignatureScanner.loadSignatures()
                self.logConsole("Signature load requested.")
            }

            for (index, file) in files.enumerated() {
                // cooperative cancellation
                if Task.isCancelled { break }

                // update UI about current file
                await MainActor.run {
                    self.currentFile = file.lastPathComponent
                    self.progressCount = index
                    self.progressFraction = total > 0 ? Double(index) / Double(total) : 0.0
                    ScanningLogger.shared.logFileScanStart(file)
                }

                // Hash file off-main (safe)
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
                    // Debug: show we are about to call the scanner
                    await MainActor.run {
                        self.logConsole("[scan] calling SignatureScanner for \(file.lastPathComponent) md5=\(md5)")
                    }

                    // Call the signature scanner on MainActor to avoid thread-safety issues.
                    // If your SignatureScanner is thread-safe, you can call it off-main to improve throughput.
                    let threat: String? = await MainActor.run {
                        SignatureScanner.scanHash(md5Hex: md5, size: fileSize)
                    }

                    // Debug log of result
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

                // small yield to allow cancellation/animation
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

                // mark progress for completed file
                await MainActor.run {
                    self.progressCount = index + 1
                    self.progressFraction = total > 0 ? Double(index + 1) / Double(total) : 1.0
                }

                // If last file, finalize
                if index + 1 == total {
                    await MainActor.run {
                        self.logConsole("Scan completed. Scanned \(total) files.")
                        ScanningLogger.shared.logScanComplete(totalFiles: total, threatsFound: self.threats.count)
                        // show results (this will drive navigation)
                        self.finishScan()
                    }
                }
            } // for

            // If task was cancelled externally, make sure we clear running flags
            await MainActor.run {
                if Task.isCancelled {
                    self.logConsole("Scan cancelled.")
                    self.isScanning = false
                    self.isFinished = false
                    // keep selectedFiles if you want the user to be able to restart
                    self.progressFraction = 0.0
                    self.currentFile = ""
                    self.showProgress = false
                    self.showResults = false
                }
            }
        } // Task.detached
    }

    func finishScan() {
        isScanning = false
        isFinished = true
        showResults = true
    }

    /// Cancel an in-progress scan and return to options.
    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil

        // Clear active flags but keep selectedFiles so user can re-run
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
        // keep a short history
        if consoleLines.last != msg {
            consoleLines.append(msg)
            if consoleLines.count > 200 { consoleLines.removeFirst(consoleLines.count - 200) }
        }
        // also print to Xcode console for debugging
        print(msg)
    }
}
