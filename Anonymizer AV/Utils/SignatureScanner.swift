import Foundation
import CryptoKit
import os.log

/// Antivirus signature scanner: loads MD5 signatures and supports heuristic analysis.
final class SignatureScanner {
    
    private static var md5Signatures: [String: String] = [:] // Key: md5:size
    private static var loaded = false
    private static let log = OSLog(subsystem: "com.luke.anonymizer", category: "SignatureScanner")
    
    private static let prefs = UserDefaults.standard
    private static let keyHeuristicEnabled = "heuristic_enabled"
    
    /// Load signatures from main.hdb (must be included in app bundle).
    /// Format: MD5:SIZE:THREAT_NAME
    static func loadSignatures() {
        guard !loaded else { return }
        
        guard let url = Bundle.main.url(forResource: "main", withExtension: "hdb") else {
            os_log("main.hdb not found in bundle", log: log, type: .error)
            ScanningLogger.shared.logSignatureError(NSError(domain: "SignatureError", code: -1, userInfo: [NSLocalizedDescriptionKey: "main.hdb not found in bundle"]))
            return
        }
        
        do {
            let data = try String(contentsOf: url, encoding: .utf8)
            data.enumerateLines { line, _ in
                let parts = line.split(separator: ":")
                if parts.count >= 3 {
                    let md5 = parts[0].lowercased()
                    let size = String(parts[1])
                    let threatName = String(parts[2])
                    md5Signatures["\(md5):\(size)"] = threatName
                }
            }
            loaded = true
            os_log("Signatures loaded: %d entries", log: log, type: .info, md5Signatures.count)
            ScanningLogger.shared.logSignatureLoading(count: md5Signatures.count)
        } catch {
            os_log("Failed to load signatures: %@", log: log, type: .error, error.localizedDescription)
            ScanningLogger.shared.logSignatureError(error)
        }
    }
    
    /// Compute MD5 hash of given data.
    private static func computeMD5(data: Data) -> String {
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    /// Scan a memory buffer for signature matches.
    static func scanBytes(buffer: Data) -> String? {
        let hash = computeMD5(data: buffer)
        let key = "\(hash):\(buffer.count)"
        return md5Signatures[key]
    }
    
    /// Scan using precomputed MD5 hash + file size.
    static func scanHash(md5Hex: String, size: Int) -> String? {
        let key = "\(md5Hex.lowercased()):\(size)"
        let result = md5Signatures[key]
        if let result = result {
            os_log("MD5 match: %@ -> %@", log: log, type: .info, key, result)
        } else {
            os_log("MD5 not found: %@", log: log, type: .debug, key)
        }
        return result
    }
    
    /// Log MD5 hash for a file
    static func logMD5Hash(for fileURL: URL, hash: String, size: Int) {
        os_log("File: %@, MD5: %@, Size: %d",
               log: log,
               type: .info,
               fileURL.lastPathComponent,
               hash,
               size)
    }
    
    /// Legacy compatibility: match by MD5 only (first hit ignoring file size).
    /// ⚠️ Use `scanHash` whenever possible.
    static func match(_ md5Hex: String) -> String? {
        for (key, value) in md5Signatures {
            if key.hasPrefix(md5Hex.lowercased() + ":") {
                return value
            }
        }
        return nil
    }
    
    /// Heuristic result wrapper
    struct HeuristicResult {
        let suspicious: Bool
        let reason: String
    }
    
    /// Heuristic scanning (enabled/disabled via UserDefaults).
    static func scanWithHeuristicsEnabledCheck(fileName: String, buffer: Data) -> HeuristicResult? {
        let heuristicEnabled = prefs.bool(forKey: keyHeuristicEnabled) || !prefs.contains(key: keyHeuristicEnabled)
        
        guard heuristicEnabled else {
            os_log("Heuristic scanning disabled", log: log, type: .debug)
            return nil
        }
        
        let scanner = HeuristicScanner()
        let result = scanner.analyzeHeuristics(fileName: fileName, buffer: buffer)
        if result.suspicious {
            os_log("Heuristic suspicious: %@", log: log, type: .info, result.reason)
            return result
        }
        return nil
    }
    
    /// Advanced heuristic scanner.
    final class HeuristicScanner {
        
        func analyzeHeuristics(fileName: String, buffer: Data) -> HeuristicResult {
            let lowerFile = fileName.lowercased()
            let preview = String(data: buffer.prefix(4096), encoding: .utf8)?.lowercased() ?? ""
            let entropy = calculateEntropy(buffer: buffer)
            
            // 1. Filename indicators
            if lowerFile.contains("keylogger") || lowerFile.contains("stealer") || lowerFile.contains("rat") {
                return HeuristicResult(suspicious: true, reason: "Suspicious filename pattern")
            }
            
            // 2. Entropy anomalies
            if isEntropySuspicious(fileName: lowerFile, entropy: entropy) {
                return HeuristicResult(suspicious: true, reason: "High entropy for file type")
            }
            
            // 3. Fake extension
            if hasFakeExtension(fileName: lowerFile, buffer: buffer) {
                return HeuristicResult(suspicious: true, reason: "Fake extension with mismatched header")
            }
            
            // 4. Suspicious keywords
            if containsSuspiciousKeywords(preview) {
                return HeuristicResult(suspicious: true, reason: "Suspicious scripting content")
            }
            
            // 5. Packer detection
            if preview.contains("upx") && preview.contains("packed") {
                return HeuristicResult(suspicious: true, reason: "UPX packer detected")
            }
            
            // 6. Dropper behavior
            if preview.contains("drop") && preview.contains(".exe") {
                return HeuristicResult(suspicious: true, reason: "Dropper behavior detected")
            }
            
            // 7. Self-modifying code
            if preview.contains(".text") && preview.contains(".data") && preview.contains("virtualalloc") {
                return HeuristicResult(suspicious: true, reason: "Self-modifying code behavior")
            }
            
            // 8. Obfuscated env manipulation
            if preview.contains("set ") && preview.contains("%") && preview.contains("=") {
                return HeuristicResult(suspicious: true, reason: "Obfuscated environment variable usage")
            }
            
            return HeuristicResult(suspicious: false, reason: "Clean")
        }
        
        private func isEntropySuspicious(fileName: String, entropy: Double) -> Bool {
            if fileName.hasSuffix(".jpg") || fileName.hasSuffix(".jpeg") || fileName.hasSuffix(".png") {
                return entropy > 8.5
            } else if fileName.hasSuffix(".txt") || fileName.hasSuffix(".html") || fileName.hasSuffix(".xml") {
                return entropy > 6.5
            } else if fileName.hasSuffix(".exe") || fileName.hasSuffix(".dll") || fileName.hasSuffix(".apk") {
                return entropy > 7.5
            } else if fileName.hasSuffix(".zip") || fileName.hasSuffix(".pdf") || fileName.hasSuffix(".docx") {
                return entropy > 8.2
            }
            return entropy > 8.0
        }
        
        private func hasFakeExtension(fileName: String, buffer: Data) -> Bool {
            if fileName.hasSuffix(".jpg") {
                return !buffer.starts(with: [0xFF, 0xD8])
            } else if fileName.hasSuffix(".png") {
                return !buffer.starts(with: [0x89, 0x50, 0x4E, 0x47])
            } else if fileName.hasSuffix(".pdf") {
                return !buffer.starts(with: [0x25, 0x50, 0x44, 0x46])
            } else if fileName.hasSuffix(".docx") {
                return !buffer.starts(with: [0x50, 0x4B, 0x03, 0x04])
            }
            return false
        }
        
        private func containsSuspiciousKeywords(_ content: String) -> Bool {
            return content.contains("powershell") ||
                   content.contains("base64") ||
                   content.contains("cmd.exe") ||
                   content.contains("/bin/sh") ||
                   content.contains("wget") ||
                   content.contains("curl") ||
                   content.contains("vbs") ||
                   content.contains("script") ||
                   content.contains("eval(") ||
                   content.contains("document.write")
        }
        
        private func calculateEntropy(buffer: Data) -> Double {
            var freq = [Int](repeating: 0, count: 256)
            for byte in buffer {
                freq[Int(byte)] += 1
            }
            var entropy = 0.0
            let length = Double(buffer.count)
            for f in freq where f > 0 {
                let p = Double(f) / length
                entropy -= p * log2(p)
            }
            return entropy
        }
    }
}

// MARK: - Helpers
private extension UserDefaults {
    func contains(key: String) -> Bool {
        return object(forKey: key) != nil
    }
}
