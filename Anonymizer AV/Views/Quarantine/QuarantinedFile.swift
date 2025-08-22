// ------------------------------------------------------------
// QuarantinedFile.swift
// DTO for UI + mapping from Core Data
// ------------------------------------------------------------

import Foundation

/// UI DTO for a quarantined file. Maps to/from Core Data `QuarantineEntity`.
struct QuarantinedFile: Identifiable, Codable, Equatable {
    let id: UUID
    var fileName: String
    var filePath: String
    var originalPath: String
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
        originalPath: String,
        dateQuarantined: Date = Date(),
        classification: String,
        reason: String? = nil,
        status: Status = .quarantined
    ) {
        self.id = id
        self.fileName = fileName
        self.filePath = filePath
        self.originalPath = originalPath
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
        self.filePath = entity.filePath
        self.originalPath = entity.originalPath
        self.dateQuarantined = entity.dateQuarantined
        self.classification = entity.classification
        self.reason = entity.reason
        self.status = .quarantined
    }
}
