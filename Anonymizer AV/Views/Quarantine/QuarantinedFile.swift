// QuarantinedFile.swift
import Foundation

struct QuarantinedFile: Identifiable, Codable, Equatable {
    let id: UUID
    var fileName: String
    var filePath: String
    var dateQuarantined: Date
    var threatName: String
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
        threatName: String,
        reason: String? = nil,
        status: Status = .quarantined
    ) {
        self.id = id
        self.fileName = fileName
        self.filePath = filePath
        self.dateQuarantined = dateQuarantined
        self.threatName = threatName
        self.reason = reason
        self.status = status
    }
}
