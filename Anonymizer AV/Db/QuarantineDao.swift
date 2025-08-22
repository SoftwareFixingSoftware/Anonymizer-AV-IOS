import Foundation
import CoreData

final class QuarantineDao {
    private let context = QuarantineDatabase.shared.context

    func insert(fileName: String,
                classification: String,
                reason: String,
                filePath: String,
                originalPath: String) {
        let entity = QuarantineEntity(context: context)
        entity.id = UUID()
        entity.fileName = fileName
        entity.classification = classification
        entity.reason = reason
        entity.dateQuarantined = Date()
        entity.filePath = filePath
        entity.originalPath = originalPath

        QuarantineDatabase.shared.saveContext()
    }

    func getAll() -> [QuarantineEntity] {
        let request: NSFetchRequest<QuarantineEntity> = QuarantineEntity.fetchRequest()
        do {
            return try context.fetch(request)
        } catch {
            print("Fetch all error: \(error)")
            return []
        }
    }

    func getById(_ id: UUID) -> QuarantineEntity? {
        let request: NSFetchRequest<QuarantineEntity> = QuarantineEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try? context.fetch(request).first
    }

    func delete(_ entity: QuarantineEntity) {
        context.delete(entity)
        QuarantineDatabase.shared.saveContext()
    }
}
