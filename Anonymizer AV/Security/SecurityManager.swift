// SecurityManager.swift
// Small adapter around QuarantineManager
import Foundation

final class SecurityManager {
    static let shared = SecurityManager()
    private init() {}

    /// Quarantine using a security-scoped URL when available.
    func moveToQuarantine(_ url: URL, classification: String, reason: String) -> Bool {
        return QuarantineManager.shared.quarantineFile(url: url, classification: classification, reason: reason)
    }

    /// Compatibility: path-based API — converts to a file:// URL and calls the URL-based overload.
    func moveToQuarantine(atPath path: String, classification: String, reason: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        return QuarantineManager.shared.quarantineFile(url: url, classification: classification, reason: reason)
    }

    func restoreFromQuarantine(id: UUID) -> Bool {
        return QuarantineManager.shared.restoreFile(id: id)
    }

    func deleteFromQuarantine(id: UUID) -> Bool {
        return QuarantineManager.shared.deleteFile(id: id)
    }

    func listQuarantined() -> [QuarantineEntity] {
        return QuarantineManager.shared.listQuarantined()
    }
}
