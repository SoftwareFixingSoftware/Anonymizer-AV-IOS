import Foundation

final class QuarantineManager {
    static let shared = QuarantineManager()
    private let dao = QuarantineDao()

    private init() {}

    // MARK: - Quarantine Directory
    private func quarantineDirectory() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Quarantine", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    // MARK: - Quarantine File
    func quarantineFile(at originalPath: String, classification: String, reason: String) -> Bool {
        let sourceURL = URL(fileURLWithPath: originalPath)
        let quarantineURL = quarantineDirectory().appendingPathComponent(sourceURL.lastPathComponent)
        do {
            try FileManager.default.moveItem(at: sourceURL, to: quarantineURL)
            dao.insert(
                fileName: sourceURL.lastPathComponent,
                classification: classification,
                reason: reason,
                filePath: quarantineURL.path,
                originalPath: originalPath
            )
            return true
        } catch {
            print("Quarantine move failed: \(error)")
            return false
        }
    }

    // MARK: - Restore File
    func restoreFile(id: UUID) -> Bool {
        guard let entity = dao.getById(id) else { return false }
        let quarantineURL = URL(fileURLWithPath: entity.filePath)
        let originalURL = URL(fileURLWithPath: entity.originalPath)
        do {
            try FileManager.default.moveItem(at: quarantineURL, to: originalURL)
            dao.delete(entity)
            return true
        } catch {
            print("Restore failed: \(error)")
            return false
        }
    }

    // MARK: - Delete File
    func deleteFile(id: UUID) -> Bool {
        guard let entity = dao.getById(id) else { return false }
        let quarantineURL = URL(fileURLWithPath: entity.filePath)
        do {
            if FileManager.default.fileExists(atPath: quarantineURL.path) {
                try FileManager.default.removeItem(at: quarantineURL)
            }
            dao.delete(entity)
            return true
        } catch {
            print("Delete failed: \(error)")
            return false
        }
    }

    // MARK: - Query
    func listQuarantined() -> [QuarantineEntity] {
        return dao.getAll()
    }

    func getFile(byId id: UUID) -> QuarantineEntity? {
        return dao.getById(id)
    }
}
