// QuarantineDao.swift
// Core Data DAO for quarantine entries.
// Stores quarantined filename (lastPathComponent) instead of absolute path going forward.
// Includes a small migration helper to convert old absolute paths when possible.

import Foundation
import CoreData

final class QuarantineDao {
    private let context = QuarantineDatabase.shared.context
    private let fileManager = FileManager.default

    // Insert: note we store only the quarantined filename (lastPathComponent) in entity.filePath
    func insert(fileName: String,
                classification: String,
                reason: String,
                filePath: String,    // pass dest.path here
                originalPath: String) {
        let entity = QuarantineEntity(context: context)
        entity.id = UUID()
        entity.fileName = fileName
        entity.classification = classification
        entity.reason = reason
        entity.dateQuarantined = Date()

        // Persist only the filename portion to avoid container-specific absolute paths
        let quarantinedFileName = URL(fileURLWithPath: filePath).lastPathComponent
        entity.filePath = quarantinedFileName

        entity.originalPath = originalPath

        QuarantineDatabase.shared.saveContext()
    }

    // Fetch all entities
    func getAll() -> [QuarantineEntity] {
        let request: NSFetchRequest<QuarantineEntity> = QuarantineEntity.fetchRequest()
        do {
            return try context.fetch(request)
        } catch {
            print("QuarantineDao.getAll: Fetch error: \(error)")
            return []
        }
    }

    // Fetch by id
    func getById(_ id: UUID) -> QuarantineEntity? {
        let request: NSFetchRequest<QuarantineEntity> = QuarantineEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        do {
            return try context.fetch(request).first
        } catch {
            print("QuarantineDao.getById: Fetch error: \(error)")
            return nil
        }
    }

    // Delete entity
    func delete(_ entity: QuarantineEntity) {
        context.delete(entity)
        QuarantineDatabase.shared.saveContext()
    }

    // Update stored filePath (store just filename)
    @discardableResult
    func updateFilePathToFilename(forId id: UUID, filename: String) -> Bool {
        guard let ent = getById(id) else { return false }
        ent.filePath = filename
        QuarantineDatabase.shared.saveContext()
        return true
    }

    // MARK: - Migration helper (run once after you deploy this change)
    // Converts existing records that stored absolute paths into filename-only records
    // when the quarantined file exists in the current quarantine directory.
    //
    // This is optional — code elsewhere is compatible with both old and new rows,
    // but running this cleans your DB and avoids fallbacks later.
    func migrateAbsolutePathsToFilename() {
        let entities = getAll()
        guard !entities.isEmpty else { return }

        let qDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("Quarantine", isDirectory: true)

        for ent in entities {
            let stored = ent.filePath
            // skip if already filename-only (not starting with '/')
            if stored.hasPrefix("/") {
                let storedURL = URL(fileURLWithPath: stored)
                let candidateName = storedURL.lastPathComponent
                let candidateInCurrent = qDir.appendingPathComponent(candidateName)
                if fileManager.fileExists(atPath: candidateInCurrent.path) {
                    // Update DB entry to store only the filename
                    ent.filePath = candidateName
                    print("QuarantineDao.migration: updated entity \(ent.id) to filename-only: \(candidateName)")
                } else {
                    // No matching file in current container; leave as-is (can't migrate)
                    print("QuarantineDao.migration: entity \(ent.id) points to path in different container and no match found.")
                }
            } else {
                // already filename-only
            }
        }

        QuarantineDatabase.shared.saveContext()
    }
}
