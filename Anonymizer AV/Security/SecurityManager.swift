// ------------------------------------------------------------
// SecurityManager.swift
// Handles delete and quarantine actions
// ------------------------------------------------------------

import Foundation

final class SecurityManager {
    static let shared = SecurityManager()
    private init() {}

    // MARK: - Delete File
    func deleteFile(_ url: URL) -> Bool {
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
                print("File deleted: \(url.path)")
                return true
            } else {
                print("Delete failed: File not found at \(url.path)")
                return false
            }
        } catch {
            print("Delete failed: \(error)")
            return false
        }
    }

    // MARK: - Move to Quarantine
    func moveToQuarantine(_ url: URL, classification: String, reason: String) -> Bool {
        let manager = QuarantineManager.shared
        return manager.quarantineFile(
            at: url.path,
            classification: classification,
            reason: reason
        )
    }

    // MARK: - Restore from Quarantine
    func restoreFromQuarantine(id: UUID) -> Bool {
        return QuarantineManager.shared.restoreFile(id: id)
    }

    // MARK: - Delete from Quarantine
    func deleteFromQuarantine(id: UUID) -> Bool {
        return QuarantineManager.shared.deleteFile(id: id)
    }

    // MARK: - List Quarantined
    func listQuarantined() -> [QuarantineEntity] {
        return QuarantineManager.shared.listQuarantined()
    }
}
