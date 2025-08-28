// QuarantinedFile.swift
// DTO used by UI, maps Core Data entity to UI model.
// Reconstructs absolute file path in this app's quarantine directory if the DB contains only a filename.

import Foundation

/// UI DTO for a quarantined file. Maps to/from Core Data `QuarantineEntity`.
struct QuarantinedFile: Identifiable, Codable, Equatable {
    let id: UUID
    var fileName: String
    var filePath: String          // absolute path to the quarantined copy for runtime use
    var dateQuarantined: Date
    var classification: String
    var reason: String?
    var status: Status

    enum Status: String, Codable {
        case quarantined
        case restored
        case deleted
    }

    init(
        id: UUID = UUID(),
        fileName: String,
        filePath: String,
        dateQuarantined: Date = Date(),
        classification: String,
        reason: String? = nil,
        status: Status = .quarantined
    ) {
        self.id = id
        self.fileName = fileName
        self.filePath = filePath
        self.dateQuarantined = dateQuarantined
        self.classification = classification
        self.reason = reason
        self.status = status
    }
}

// MARK: - Mapping from Core Data entity
extension QuarantinedFile {
    init(entity: QuarantineEntity) {
        self.id = entity.id
        self.fileName = entity.fileName
        self.dateQuarantined = entity.dateQuarantined
        self.classification = entity.classification
        self.reason = entity.reason

        // entity.filePath might be:
        //  - a filename (preferred: what we started storing going forward), or
        //  - an absolute path (older rows). Handle both.
        let stored = entity.filePath

        if stored.hasPrefix("/") {
            // Old-style absolute path was stored; keep it for compatibility.
            self.filePath = stored
        } else {
            // New-style: stored is just the quarantined filename -> reconstruct absolute path in current container
            let qDir = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first!.appendingPathComponent("Quarantine", isDirectory: true)

            let full = qDir.appendingPathComponent(stored)
            self.filePath = full.path
        }

        self.status = .quarantined
    }
}
