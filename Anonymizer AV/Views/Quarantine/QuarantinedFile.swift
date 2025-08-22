// QuarantinedFile.swift
import Foundation

/// UI DTO for a quarantined file. Maps to/from Core Data `QuarantineEntity`.
struct QuarantinedFile: Identifiable, Codable, Equatable {
    let id: UUID
    var fileName: String
    var filePath: String
    var dateQuarantined: Date
    var classification: String          // previously called threatName
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
        self.filePath = entity.filePath
        self.dateQuarantined = entity.dateQuarantined
        self.classification = entity.classification
        self.reason = entity.reason
        self.status = .quarantined
    }
}
