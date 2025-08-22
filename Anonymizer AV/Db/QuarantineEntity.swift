import Foundation
import CoreData

@objc(QuarantineEntity)
public class QuarantineEntity: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var fileName: String
    @NSManaged public var classification: String
    @NSManaged public var dateQuarantined: Date
    @NSManaged public var reason: String
    @NSManaged public var filePath: String
    @NSManaged public var originalPath: String
}

extension QuarantineEntity {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<QuarantineEntity> {
        return NSFetchRequest<QuarantineEntity>(entityName: "QuarantineEntity")
    }
}
