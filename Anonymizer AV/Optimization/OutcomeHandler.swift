//
// OutcomeHandler.swift
// Centralized safe operations: backup-only, audit trail, restore guidance
//

import Foundation
import Contacts
import Photos
import EventKit
import UIKit

// Single source-of-truth notification name (kept for non-destructive events only)
extension Notification.Name {
    static let didCreateBackupRecord = Notification.Name("didCreateBackupRecord")
}

// MARK: - Outcome model types
enum OutcomeType: String, Codable {
    case contacts
    case files
    case media
    case calendar
}

enum OutcomeActionKind: String, Codable {
    case backupOnly
}

struct ActionRecord: Codable, Identifiable {
    let id: UUID
    let type: OutcomeType
    let kind: OutcomeActionKind
    let timestamp: Date
    let summary: String
    let payload: [String: String]
    let itemsPreview: [String]
}

// MARK: - OutcomeHandler (backup-only, no destructive operations)
final class OutcomeHandler {
    static let shared = OutcomeHandler()
    private init() { loadRecords() }

    // backup directory
    private lazy var backupDirectory: URL = {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("AnonymizerBackups", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // records store (file-backed)
    private var recordsURL: URL { backupDirectory.appendingPathComponent("action_records.json") }
    private var actionRecordsCache: [ActionRecord] = []
    private let recordsQueue = DispatchQueue(label: "OutcomeHandler.records", attributes: .concurrent)

    // load persisted records
    func loadRecords() {
        recordsQueue.async(flags: .barrier) {
            if let data = try? Data(contentsOf: self.recordsURL),
               let arr = try? JSONDecoder().decode([ActionRecord].self, from: data) {
                self.actionRecordsCache = arr
            } else {
                self.actionRecordsCache = []
            }
        }
    }

    // save one record (atomic write)
    func saveRecord(_ r: ActionRecord) {
        recordsQueue.async(flags: .barrier) {
            self.actionRecordsCache.insert(r, at: 0)
            if let data = try? JSONEncoder().encode(self.actionRecordsCache) {
                try? data.write(to: self.recordsURL, options: .atomic)
            }
            // notify optionally that a backup record was created
            NotificationCenter.default.post(name: .didCreateBackupRecord, object: r)
        }
    }

    func getRecords() -> [ActionRecord] {
        return recordsQueue.sync { actionRecordsCache }
    }

    func removeRecord(id: UUID) {
        recordsQueue.async(flags: .barrier) {
            self.actionRecordsCache.removeAll { $0.id == id }
            if let data = try? JSONEncoder().encode(self.actionRecordsCache) {
                try? data.write(to: self.recordsURL, options: .atomic)
            }
        }
    }

    // MARK: - Contacts: backup (vCard)
    /// Backup contacts to a vCard file and return ActionRecord (does not alter store)
    func backupContacts(_ contacts: [CNContact]) async throws -> ActionRecord {
        let data = try CNContactVCardSerialization.data(with: contacts)
        let path = backupDirectory.appendingPathComponent("contacts-backup-\(UUID().uuidString).vcf")
        try data.write(to: path, options: .atomic)
        let summary = "Contacts backup \(contacts.count) items"
        let rec = ActionRecord(id: UUID(),
                               type: .contacts,
                               kind: .backupOnly,
                               timestamp: Date(),
                               summary: summary,
                               payload: ["backupPath": path.path],
                               itemsPreview: contacts.prefix(6).map { "\($0.givenName) \($0.familyName)" })
        saveRecord(rec)
        return rec
    }

    // MARK: - Files backup (copy)
    func backupFiles(_ urls: [URL]) async throws -> ActionRecord {
        var preview: [String] = []
        let folder = backupDirectory.appendingPathComponent("files-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for url in urls {
            let dest = folder.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.copyItem(at: url, to: dest)
            preview.append(url.lastPathComponent)
        }
        let rec = ActionRecord(id: UUID(), type: .files, kind: .backupOnly, timestamp: Date(), summary: "Backed up \(urls.count) files", payload: ["backupFolder": folder.path], itemsPreview: Array(preview.prefix(8)))
        saveRecord(rec)
        return rec
    }

    /// Restore files from a backup record (best-effort copy back into Documents)
    func restoreFilesFromBackup(record: ActionRecord) throws {
        guard let folderPath = record.payload["backupFolder"] else {
            throw NSError(domain: "OutcomeHandler", code: 2, userInfo: [NSLocalizedDescriptionKey: "No backup folder found in record"])
        }
        let folder = URL(fileURLWithPath: folderPath, isDirectory: true)
        let fm = FileManager.default
        let destBase = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        guard let items = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
        for src in items {
            let dest = destBase.appendingPathComponent(src.lastPathComponent)
            if fm.fileExists(atPath: dest.path) {
                // existing file — create a unique restored copy
                let restored = dest.deletingPathExtension().appendingPathExtension("restored.\(UUID().uuidString).\(dest.pathExtension)")
                try? fm.copyItem(at: src, to: restored)
            } else {
                try? fm.copyItem(at: src, to: dest)
            }
        }
    }

    // MARK: - Media backup (to album)
    func backupMediaAssets(localIdentifiers: [String], albumNamePrefix: String = "Anonymizer Backup") async throws -> ActionRecord {
        let albumName = "\(albumNamePrefix) \(Date())"
        var albumLocalId: String?
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                let _ = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumName)
            }, completionHandler: { success, error in
                if let e = error { cont.resume(throwing: e); return }
                cont.resume(returning: ())
            })
        }

        // find created album (best-effort)
        let fetch = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        fetch.enumerateObjects { coll, _, _ in
            if coll.localizedTitle == albumName { albumLocalId = coll.localIdentifier }
        }
        guard let albumId = albumLocalId else {
            throw NSError(domain: "OutcomeHandler", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unable to create album"])
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: nil)
                if let collection = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumId], options: nil).firstObject,
                   let req = PHAssetCollectionChangeRequest(for: collection) {
                    req.addAssets(fetchResult)
                }
            }, completionHandler: { success, error in
                if let e = error { cont.resume(throwing: e); return }
                cont.resume(returning: ())
            })
        }

        let rec = ActionRecord(id: UUID(), type: .media, kind: .backupOnly, timestamp: Date(), summary: "Backed up \(localIdentifiers.count) assets to album \(albumName)", payload: ["albumId": albumId, "assetIds": localIdentifiers.joined(separator: ",")], itemsPreview: Array(localIdentifiers.prefix(8)))
        saveRecord(rec)
        return rec
    }

    // MARK: - Calendar backup (ICS)
    func backupCalendarEvents(_ events: [EKEvent]) async throws -> ActionRecord {
        func eventToICS(_ e: EKEvent) -> String {
            let formatter = DateFormatter()
            formatter.timeZone = TimeZone(abbreviation: "UTC")
            formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            let dtstart = formatter.string(from: e.startDate)
            let dtend = formatter.string(from: e.endDate ?? e.startDate.addingTimeInterval(60*60))
            let title = (e.title ?? "").replacingOccurrences(of: "\n", with: "\\n")
            return """
            BEGIN:VEVENT
            UID:\(e.eventIdentifier)
            DTSTART:\(dtstart)
            DTEND:\(dtend)
            SUMMARY:\(title)
            DESCRIPTION:\(e.notes ?? "")
            END:VEVENT
            """
        }
        var body = "BEGIN:VCALENDAR\nVERSION:2.0\nCALSCALE:GREGORIAN\n"
        for ev in events { body += eventToICS(ev) + "\n" }
        body += "END:VCALENDAR\n"
        let url = backupDirectory.appendingPathComponent("calendar-backup-\(UUID().uuidString).ics")
        try body.data(using: .utf8)?.write(to: url)
        let rec = ActionRecord(id: UUID(), type: .calendar, kind: .backupOnly, timestamp: Date(), summary: "Backed up \(events.count) calendar events", payload: ["backupPath": url.path], itemsPreview: events.prefix(8).map { $0.title ?? "Untitled" })
        saveRecord(rec)
        return rec
    }

    /// NEW: Backup calendar events by identifiers (safe wrapper). Fetches events from a fresh EKEventStore, then creates ICS backup.
    func backupCalendarEventsByIdentifiers(_ identifiers: [String]) async throws -> ActionRecord {
        var eventsToBackup: [EKEvent] = []
        // Use main actor / fresh store to avoid XPC issues
        await MainActor.run {
            let store = EKEventStore()
            for id in identifiers {
                if let e = store.event(withIdentifier: id) {
                    eventsToBackup.append(e)
                } // else just skip missing ones
            }
        }
        return try await backupCalendarEvents(eventsToBackup)
    }

    // MARK: - Restore helper (contacts & calendar guidance)
    /// Restore contacts from a backup ActionRecord (vCard).
    /// This is a non-destructive add-back: it will import contacts from the vCard file.
    func restoreContactsFromBackup(record: ActionRecord) throws {
        guard let bp = record.payload["backupPath"] else {
            throw NSError(domain: "OutcomeHandler", code: 10, userInfo: [NSLocalizedDescriptionKey: "No backup vCard found"])
        }
        let url = URL(fileURLWithPath: bp)
        let data = try Data(contentsOf: url)
        let contacts = try CNContactVCardSerialization.contacts(with: data)
        let store = CNContactStore()
        let saveReq = CNSaveRequest()
        for c in contacts {
            if let mutable = try? c.mutableCopy() as? CNMutableContact {
                saveReq.add(mutable, toContainerWithIdentifier: nil)
            }
        }
        try store.execute(saveReq)
    }

    /// Guidance for restoring calendar backups: we keep an ICS file path in the record payload.
    /// We do not attempt automatic import here — the ICS can be presented to the user or shared.
    func calendarBackupPath(for record: ActionRecord) -> String? {
        return record.payload["backupPath"]
    }
}
