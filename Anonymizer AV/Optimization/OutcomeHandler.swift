//
// OutcomeHandler.swift
// Centralized safe operations: backup, commit (delete/merge), undo
//

import Foundation
import Contacts
import Photos
import EventKit
import UIKit

// Single source-of-truth notification name
extension Notification.Name {
    static let didCommitOutcomeAction = Notification.Name("didCommitOutcomeAction")
}

// MARK: - Outcome model types
enum OutcomeType: String, Codable {
    case contacts
    case files
    case media
    case calendar
}

enum OutcomeActionKind: String, Codable {
    case delete
    case merge
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

// MARK: - OutcomeHandler
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

    // MARK: - Merge concurrency guard
    private var mergesInProgress = Set<String>()
    private let mergesQueue = DispatchQueue(label: "OutcomeHandler.merges")

    private func mergeKey(base: CNContact, duplicates: [CNContact]) -> String {
        let dupIds = duplicates.map { $0.identifier }.sorted().joined(separator: ",")
        return "\(base.identifier)|\(dupIds)"
    }

    // MARK: - Contacts: backup (vCard) + merge wrapper
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

    /// Commit merge with concurrency guard (still available if you want to enable merges later)
    func commitMergeContacts(base: CNContact, duplicates: [CNContact]) async throws -> ActionRecord {
        guard !duplicates.isEmpty else {
            throw NSError(domain: "OutcomeHandler", code: 400, userInfo: [NSLocalizedDescriptionKey: "No duplicates provided"])
        }

        let key = mergeKey(base: base, duplicates: duplicates)
        var already = false
        mergesQueue.sync {
            if mergesInProgress.contains(key) { already = true }
            else { mergesInProgress.insert(key) }
        }
        if already {
            throw NSError(domain: "OutcomeHandler", code: 409, userInfo: [NSLocalizedDescriptionKey: "Merge already in progress"])
        }
        defer {
            mergesQueue.async { [weak self] in self?.mergesInProgress.remove(key) }
        }

        // create backup first
        let contacts = [base] + duplicates
        let backupRec = try await backupContacts(contacts)

        // ensure permissions
        let store = CNContactStore()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            store.requestAccess(for: .contacts) { granted, error in
                if let e = error { cont.resume(throwing: e); return }
                if granted { cont.resume(returning: ()) } else {
                    cont.resume(throwing: NSError(domain: "OutcomeHandler", code: 2, userInfo: [NSLocalizedDescriptionKey: "Contacts permission denied"]))
                }
            }
        }

        // perform merge with one retry on transient XPC invalidation
        var lastError: Error?
        for attempt in 1...2 {
            do {
                try performMergeSync(base: base, duplicates: duplicates)
                lastError = nil
                break
            } catch {
                lastError = error
                let msg = (error as NSError).localizedDescription
                if msg.contains("XPC connection was invalidated") && attempt == 1 {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    continue
                } else {
                    throw NSError(domain: "OutcomeHandler", code: 500, userInfo: [NSLocalizedDescriptionKey: "Merge failed: \(msg)"])
                }
            }
        }

        let rec = ActionRecord(id: UUID(),
                               type: .contacts,
                               kind: .merge,
                               timestamp: Date(),
                               summary: "Merged \(duplicates.count) contacts into \(base.givenName) \(base.familyName)",
                               payload: ["backupPath": backupRec.payload["backupPath"] ?? ""],
                               itemsPreview: [base.givenName + " " + base.familyName])
        saveRecord(rec)

        NotificationCenter.default.post(name: .didCommitOutcomeAction, object: rec)
        return rec
    }

    /// Synchronous merge implementation (throws)
    private func performMergeSync(base: CNContact, duplicates: [CNContact]) throws {
        let store = CNContactStore()
        let keys: [CNKeyDescriptor] = [CNContactPhoneNumbersKey, CNContactEmailAddressesKey, CNContactGivenNameKey, CNContactFamilyNameKey, CNContactIdentifierKey] as [CNKeyDescriptor]
        guard let fetchedBase = try? store.unifiedContact(withIdentifier: base.identifier, keysToFetch: keys),
              let mutableBase = try? fetchedBase.mutableCopy() as? CNMutableContact else {
            throw NSError(domain: "OutcomeHandler", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to fetch or mutate base contact"])
        }

        func normalizePhone(_ raw: String) -> String { String(raw.filter { $0.isNumber }.suffix(11)) }
        func normalizeEmail(_ raw: String) -> String { raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

        var existingPhones = Set(mutableBase.phoneNumbers.map { normalizePhone($0.value.stringValue) })
        var existingEmails = Set(mutableBase.emailAddresses.map { normalizeEmail(String($0.value)) })

        let saveReq = CNSaveRequest()
        for dup in duplicates {
            if dup.identifier == base.identifier { continue }
            for phone in dup.phoneNumbers {
                let raw = phone.value.stringValue
                let n = normalizePhone(raw)
                if n.isEmpty || existingPhones.contains(n) { continue }
                mutableBase.phoneNumbers.append(phone)
                existingPhones.insert(n)
            }
            for em in dup.emailAddresses {
                let raw = String(em.value)
                let n = normalizeEmail(raw)
                if n.isEmpty || existingEmails.contains(n) { continue }
                mutableBase.emailAddresses.append(em)
                existingEmails.insert(n)
            }
            if let dupFetched = try? store.unifiedContact(withIdentifier: dup.identifier, keysToFetch: [CNContactIdentifierKey] as [CNKeyDescriptor]),
               let dupMutable = try? dupFetched.mutableCopy() as? CNMutableContact {
                saveReq.delete(dupMutable)
            } else if let dupMutable = try? dup.mutableCopy() as? CNMutableContact {
                saveReq.delete(dupMutable)
            }
        }
        saveReq.update(mutableBase)
        try store.execute(saveReq)
    }

    /// Delete contacts (caller should backup first)
    func deleteContacts(_ contacts: [CNContact]) async throws {
        let store = CNContactStore()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            store.requestAccess(for: .contacts) { granted, error in
                if let e = error { cont.resume(throwing: e); return }
                if granted { cont.resume(returning: ()) } else {
                    cont.resume(throwing: NSError(domain: "OutcomeHandler", code: 2, userInfo: [NSLocalizedDescriptionKey: "Contacts permission denied"]))
                }
            }
        }

        let saveReq = CNSaveRequest()
        for c in contacts {
            if let fetched = try? store.unifiedContact(withIdentifier: c.identifier, keysToFetch: [CNContactIdentifierKey] as [CNKeyDescriptor]),
               let m = try? fetched.mutableCopy() as? CNMutableContact {
                saveReq.delete(m)
            } else if let m = try? c.mutableCopy() as? CNMutableContact {
                saveReq.delete(m)
            }
        }

        try store.execute(saveReq)

        let rec = ActionRecord(id: UUID(), type: .contacts, kind: .delete, timestamp: Date(), summary: "Deleted \(contacts.count) contacts", payload: [:], itemsPreview: contacts.prefix(8).map { "\($0.givenName) \($0.familyName)" })
        saveRecord(rec)
        NotificationCenter.default.post(name: .didCommitOutcomeAction, object: rec)
    }

    // MARK: - Files backup/delete
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

    func commitDeleteFiles(_ urls: [URL]) async throws -> ActionRecord {
        let backupRecord = try await backupFiles(urls)
        for url in urls { try? FileManager.default.removeItem(at: url) }
        let rec = ActionRecord(id: UUID(), type: .files, kind: .delete, timestamp: Date(), summary: "Deleted \(urls.count) files", payload: ["backupFolder": backupRecord.payload["backupFolder"] ?? ""], itemsPreview: urls.prefix(8).map { $0.lastPathComponent })
        saveRecord(rec)
        NotificationCenter.default.post(name: .didCommitOutcomeAction, object: rec)
        return rec
    }

    func undoFilesDelete(record: ActionRecord) async throws {
        guard let folderPath = record.payload["backupFolder"] else {
            throw NSError(domain: "OutcomeHandler", code: 2, userInfo: [NSLocalizedDescriptionKey: "No backup folder"])
        }
        let folder = URL(fileURLWithPath: folderPath, isDirectory: true)
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
        for src in items {
            let dest = fm.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent(src.lastPathComponent)
            if fm.fileExists(atPath: dest.path) {
                let dest2 = dest.deletingPathExtension().appendingPathExtension("restored.\(UUID().uuidString).\(dest.pathExtension)")
                try? fm.copyItem(at: src, to: dest2)
            } else {
                try? fm.copyItem(at: src, to: dest)
            }
        }
    }

    // MARK: - Media backup/delete
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

    func commitDeleteMedia(localIdentifiers: [String]) async throws -> ActionRecord {
        let backup = try await backupMediaAssets(localIdentifiers: localIdentifiers)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                let assets = PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: nil)
                PHAssetChangeRequest.deleteAssets(assets)
            }, completionHandler: { success, error in
                if let e = error { cont.resume(throwing: e); return }
                cont.resume(returning: ())
            })
        }
        let rec = ActionRecord(id: UUID(), type: .media, kind: .delete, timestamp: Date(), summary: "Deleted \(localIdentifiers.count) media", payload: backup.payload, itemsPreview: Array(localIdentifiers.prefix(8)))
        saveRecord(rec)
        NotificationCenter.default.post(name: .didCommitOutcomeAction, object: rec)
        return rec
    }

    func undoMediaDelete(record: ActionRecord) async throws {
        // Best-effort guidance only — recommend user restore from backup album in Photos app
        guard let albumId = record.payload["albumId"] else {
            throw NSError(domain: "OutcomeHandler", code: 4, userInfo: [NSLocalizedDescriptionKey: "No album info for undo"])
        }
        print("[OutcomeHandler] undoMediaDelete: backup album \(albumId)")
    }

    // MARK: - Calendar backup/delete
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

    func commitDeleteCalendarEvents(_ events: [EKEvent]) async throws -> ActionRecord {
        let backup = try await backupCalendarEvents(events)
        let store = EKEventStore()
        for e in events { try store.remove(e, span: .futureEvents, commit: false) }
        try store.commit()
        let rec = ActionRecord(id: UUID(), type: .calendar, kind: .delete, timestamp: Date(), summary: "Deleted \(events.count) events", payload: backup.payload, itemsPreview: events.prefix(8).map { $0.title ?? "Untitled" })
        saveRecord(rec)
        NotificationCenter.default.post(name: .didCommitOutcomeAction, object: rec)
        return rec
    }

    // MARK: - Undo generic
    func undo(_ record: ActionRecord) async throws {
        switch record.type {
        case .contacts:
            if record.kind == .delete || record.kind == .merge {
                if let bp = record.payload["backupPath"] {
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
                } else {
                    throw NSError(domain: "OutcomeHandler", code: 10, userInfo: [NSLocalizedDescriptionKey: "No backup vCard found"])
                }
            }
        case .files:
            try await undoFilesDelete(record: record)
        case .media:
            try await undoMediaDelete(record: record)
        case .calendar:
            if let bp = record.payload["backupPath"] {
                print("[OutcomeHandler] ICS backup at \(bp). Manual import recommended.")
            }
        }
    }
}
