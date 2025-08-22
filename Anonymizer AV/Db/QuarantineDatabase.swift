import Foundation
import CoreData

final class QuarantineDatabase {
    static let shared = QuarantineDatabase()

    private let container: NSPersistentContainer

    private init() {
        container = NSPersistentContainer(name: "QuarantineModel") // must match .xcdatamodeld filename
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Failed to load Core Data stack: \(error)")
            }
        }
    }

    var context: NSManagedObjectContext {
        return container.viewContext
    }

    func saveContext() {
        let context = container.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                print("Core Data save error: \(error)")
            }
        }
    }
}
