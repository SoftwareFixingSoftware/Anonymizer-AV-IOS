//
// OutcomeHandler.swift
// Centralized safe operations: backup, commit (delete/merge), undo
//

import Foundation
import Contacts
import Photos
import EventKit
import MobileCoreServices
import UIKit

enum OutcomeType: String, Codable {
    case contacts
    case files
    case media // photos & videos (PHAsset localIdentifiers)
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
    // human summary
    let summary: String
    // payload (type-specific)
    let payload: [String: String] // flexible small kv-store: e.g. backupPath, albumLocalIdentifier, assetIDs csv, contactBackupPath
    // optionally, keep list of item identifiers (small sample) for quick UI
    let itemsPreview: [String]
}

final class OutcomeHandler {
    static let shared = OutcomeHandler()
    private init() {}

    // where backups live
    private lazy var backupDirectory: URL = {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("AnonymizerBackups", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // MARK: - Records store (simple file-backed)
    private var recordsURL: URL {
        return backupDirectory.appendingPathComponent("action_records.json")
    }

    private var actionRecordsCache: [ActionRecord] = []
    private let recordsQueue = DispatchQueue(label: "OutcomeHandler.records")

    func loadRecords() {
        recordsQueue.sync {
            if let data = try? Data(contentsOf: recordsURL),
               let arr = try? JSONDecoder().decode([ActionRecord].self, from: data) {
                actionRecordsCache = arr
            } else {
                actionRecordsCache = []
            }
        }
    }

    func saveRecord(_ r: ActionRecord) {
        recordsQueue.async {
            // Keep as recent (insert into position 1 as legacy behaviour)
            self.actionRecordsCache.insert(r, at: 1)
            if let data = try? JSONEncoder().encode(self.actionRecordsCache) {
                try? data.write(to: self.recordsURL, options: .atomic)
            }
        }
    }

    func getRecords() -> [ActionRecord] {
        return recordsQueue.sync { actionRecordsCache }
    }

    func removeRecord(id: UUID) {
        recordsQueue.async {
            self.actionRecordsCache.removeAll { $0.id == id }
            if let data = try? JSONEncoder().encode(self.actionRecordsCache) {
                try? data.write(to: self.recordsURL, options: .atomic)
            }
        }
    }

    // MARK: - Contacts: backup (vCard) + merge wrapper
    /// Returns ActionRecord (with backup path) but DOES NOT perform merge. Use `commitMergeContacts` to commit.
    func backupContacts(_ contacts: [CNContact]) async throws -> ActionRecord {
        print("[Outcome] backupContacts start count=\(contacts.count)")
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
        print("[Outcome] backupContacts done -> \(path.path)")
        return rec
    }

    /// Merge invocation that also logs the action and keeps a backup (vCard).
    /// Retries once on transient XPC invalidation and ensures permission check up-front.
    func commitMergeContacts(base: CNContact, duplicates: [CNContact]) async throws -> ActionRecord {
        print("[Outcome] commitMergeContacts START base=\(base.identifier) dupCount=\(duplicates.count)")

        // Backup group first
        let contacts = [base] + duplicates
        let backupRec = try await backupContacts(contacts)

        // Ensure we have permission up-front (avoid mid-operation XPC failures)
        let accessStore = CNContactStore()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            accessStore.requestAccess(for: .contacts) { granted, error in
                if let e = error { cont.resume(throwing: e); return }
                if granted { cont.resume(returning: ()) }
                else { cont.resume(throwing: NSError(domain: "OutcomeHandler", code: 2, userInfo: [NSLocalizedDescriptionKey: "Contacts permission denied"])) }
            }
        }

        // perform merge with retry on transient XPC invalidation
        var lastError: Error?
        for attempt in 1...2 {
            do {
                // performMergeSync internally uses a fresh CNContactStore
                try performMergeSync(base: base, duplicates: duplicates)
                print("[Outcome] commitMergeContacts SUCCEEDED on attempt \(attempt)")
                lastError = nil
                break
            } catch {
                lastError = error
                let msg = (error as NSError).localizedDescription
                print("[Outcome] commitMergeContacts attempt \(attempt) error: \(msg)")
                if msg.contains("XPC connection was invalidated") && attempt == 1 {
                    // small backoff then retry
                    try await Task.sleep(nanoseconds: 250_000_000) // 250ms
                    continue
                } else {
                    throw error
                }
            }
        }

        if let err = lastError {
            print("[Outcome] commitMergeContacts finished with lastError: \(err)")
        }

        // Log action with pointer to backup file
        let rec = ActionRecord(id: UUID(),
                               type: .contacts,
                               kind: .merge,
                               timestamp: Date(),
                               summary: "Merged \(duplicates.count) contacts into \(base.givenName) \(base.familyName)",
                               payload: ["backupPath": backupRec.payload["backupPath"] ?? ""],
                               itemsPreview: [base.givenName + " " + base.familyName])
        saveRecord(rec)
        print("[Outcome] commitMergeContacts DONE rec.id=\(rec.id)")
        return rec
    }

    /// Synchronous merge logic (throws) — uses a fresh CNContactStore implicitly via save request
    private func performMergeSync(base: CNContact, duplicates: [CNContact]) throws {
        let store = CNContactStore()
        let keys: [CNKeyDescriptor] = [CNContactPhoneNumbersKey, CNContactEmailAddressesKey, CNContactGivenNameKey, CNContactFamilyNameKey, CNContactIdentifierKey] as [CNKeyDescriptor]
        guard let fetchedBase = try? store.unifiedContact(withIdentifier: base.identifier, keysToFetch: keys),
              let mutableBase = try? fetchedBase.mutableCopy() as? CNMutableContact else {
            throw NSError(domain: "OutcomeHandler", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to fetch/mutate base contact"])
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

    /// Delete contacts (by CNContact)
    func deleteContacts(_ contacts: [CNContact]) async throws {
        let store = CNContactStore()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            store.requestAccess(for: .contacts) { granted, error in
                if let e = error { cont.resume(throwing: e); return }
                if granted { cont.resume(returning: ()) }
                else { cont.resume(throwing: NSError(domain: "OutcomeHandler", code: 2, userInfo: [NSLocalizedDescriptionKey: "Contacts permission denied"])) }
            }
        }

        let saveReq = CNSaveRequest()
        for c in contacts {
            // fetch the current unified contact and delete its mutable copy
            if let fetched = try? store.unifiedContact(withIdentifier: c.identifier, keysToFetch: [CNContactIdentifierKey] as [CNKeyDescriptor]),
               let m = try? fetched.mutableCopy() as? CNMutableContact {
                saveReq.delete(m)
            } else if let m = try? c.mutableCopy() as? CNMutableContact {
                saveReq.delete(m)
            }
        }
        try store.execute(saveReq)
    }

    // MARK: - Files: backup (copy) + delete & undo
    /// Copies files to backup dir and returns ActionRecord
    func backupFiles(_ urls: [URL]) async throws -> ActionRecord {
        print("[Outcome] backupFiles start count=\(urls.count)")
        var preview: [String] = []
        var payload: [String: String] = [:]
        let folder = backupDirectory.appendingPathComponent("files-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for url in urls {
            let dest = folder.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.copyItem(at: url, to: dest)
            preview.append(url.lastPathComponent)
        }
        payload["backupFolder"] = folder.path
        let rec = ActionRecord(id: UUID(), type: .files, kind: .backupOnly, timestamp: Date(), summary: "Backed up \(urls.count) files", payload: payload, itemsPreview: Array(preview.prefix(8)))
        saveRecord(rec)
        print("[Outcome] backupFiles done folder=\(folder.path)")
        return rec
    }

    /// Commit delete for files: backup then delete originals; returns ActionRecord with backup path
    func commitDeleteFiles(_ urls: [URL]) async throws -> ActionRecord {
        print("[Outcome] commitDeleteFiles start count=\(urls.count)")
        let backupRecord = try await backupFiles(urls)
        // now delete originals
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
        let rec = ActionRecord(id: UUID(), type: .files, kind: .delete, timestamp: Date(), summary: "Deleted \(urls.count) files", payload: ["backupFolder": backupRecord.payload["backupFolder"] ?? ""], itemsPreview: urls.prefix(8).map { $0.lastPathComponent })
        saveRecord(rec)
        print("[Outcome] commitDeleteFiles done rec.id=\(rec.id)")
        return rec
    }

    /// Undo file delete: copy from backup folder back to original names (best-effort)
    func undoFilesDelete(record: ActionRecord) async throws {
        guard let folderPath = record.payload["backupFolder"] ?? record.payload["backupFolder"] else {
            throw NSError(domain: "OutcomeHandler", code: 2, userInfo: [NSLocalizedDescriptionKey: "No backup folder"])
        }
        let folder = URL(fileURLWithPath: folderPath, isDirectory: true)
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
        for src in items {
            let dest = fm.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent(src.lastPathComponent)
            if fm.fileExists(atPath: dest.path) {
                // avoid overwrite — append suffix
                let dest2 = dest.deletingPathExtension().appendingPathExtension("restored.\(UUID().uuidString).\(dest.pathExtension)")
                try? fm.copyItem(at: src, to: dest2)
            } else {
                try? fm.copyItem(at: src, to: dest)
            }
        }
    }

    // MARK: - Media (Photos/Videos): create backup album (safe) and delete assets
    /// Create a backup album and add the given asset local identifiers
    func backupMediaAssets(localIdentifiers: [String], albumNamePrefix: String = "Anonymizer Backup") async throws -> ActionRecord {
        print("[Outcome] backupMediaAssets start count=\(localIdentifiers.count)")
        // Create album
        let albumName = "\(albumNamePrefix) \(Date())"
        var albumLocalId: String?
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                let _ = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumName)
            } completionHandler: { success, error in
                if let e = error { cont.resume(throwing: e); return }
                cont.resume(returning: ())
            }
        }

        // fetch the created album (best-effort)
        let fetch = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        fetch.enumerateObjects { coll, _, _ in
            if coll.localizedTitle == albumName { albumLocalId = coll.localIdentifier }
        }

        guard let albumId = albumLocalId else {
            throw NSError(domain: "OutcomeHandler", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unable to create album"])
        }

        // add assets to album
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

        // Log record with album id and asset ids
        let rec = ActionRecord(id: UUID(), type: .media, kind: .backupOnly, timestamp: Date(), summary: "Backed up \(localIdentifiers.count) assets to album \(albumName)", payload: ["albumId": albumId, "assetIds": localIdentifiers.joined(separator: "," )], itemsPreview: Array(localIdentifiers.prefix(8)))
        saveRecord(rec)
        print("[Outcome] backupMediaAssets done albumId=\(albumId)")
        return rec
    }

    /// Commit delete for media assets (permanent or to Recently Deleted via Photos)
    func commitDeleteMedia(localIdentifiers: [String]) async throws -> ActionRecord {
        print("[Outcome] commitDeleteMedia start count=\(localIdentifiers.count)")
        // backup to album first
        let backup = try await backupMediaAssets(localIdentifiers: localIdentifiers)
        // Now delete
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
        print("[Outcome] commitDeleteMedia done rec.id=\(rec.id)")
        return rec
    }

    /// Undo media delete is a best-effort: assets deleted go to Recently Deleted; we recommend user restore via Photos app.
    func undoMediaDelete(record: ActionRecord) async throws {
        guard let albumId = record.payload["albumId"],
              let assetIds = record.payload["assetIds"] else {
            throw NSError(domain: "OutcomeHandler", code: 4, userInfo: [NSLocalizedDescriptionKey: "No album info for undo"])
        }
        print("[Outcome] undoMediaDelete info albumId=\(albumId) assetCount=\(assetIds.split(separator: ",").count)")
        // Best-effort: instruct user to restore manually from backup album
    }

    // MARK: - Calendar: export to ICS + delete
    func backupCalendarEvents(_ events: [EKEvent]) async throws -> ActionRecord {
        print("[Outcome] backupCalendarEvents start count=\(events.count)")
        // Simple ICS serialization (minimal fields)
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
        for ev in events {
            body += eventToICS(ev) + "\n"
        }
        body += "END:VCALENDAR\n"
        let url = backupDirectory.appendingPathComponent("calendar-backup-\(UUID().uuidString).ics")
        try body.data(using: .utf8)?.write(to: url)
        let rec = ActionRecord(id: UUID(), type: .calendar, kind: .backupOnly, timestamp: Date(), summary: "Backed up \(events.count) calendar events", payload: ["backupPath": url.path], itemsPreview: events.prefix(8).map { $0.title ?? "Untitled" })
        saveRecord(rec)
        print("[Outcome] backupCalendarEvents done -> \(url.path)")
        return rec
    }

    func commitDeleteCalendarEvents(_ events: [EKEvent]) async throws -> ActionRecord {
        print("[Outcome] commitDeleteCalendarEvents start count=\(events.count)")
        let backup = try await backupCalendarEvents(events)
        // delete via EKEventStore
        let store = EKEventStore()
        for e in events {
            try store.remove(e, span: .futureEvents, commit: false)
        }
        try store.commit()
        let rec = ActionRecord(id: UUID(), type: .calendar, kind: .delete, timestamp: Date(), summary: "Deleted \(events.count) events", payload: backup.payload, itemsPreview: events.prefix(8).map { $0.title ?? "Untitled" })
        saveRecord(rec)
        print("[Outcome] commitDeleteCalendarEvents done rec.id=\(rec.id)")
        return rec
    }

    // MARK: - Undo generic
    func undo(_ record: ActionRecord) async throws {
        print("[Outcome] undo start id=\(record.id) type=\(record.type) kind=\(record.kind)")
        switch record.type {
        case .contacts:
            if record.kind == .delete || record.kind == .merge {
                if let bp = record.payload["backupPath"] {
                    // restore by importing vCard
                    let url = URL(fileURLWithPath: bp)
                    if let data = try? Data(contentsOf: url) {
                        let contacts = try CNContactVCardSerialization.contacts(with: data)
                        // import into store
                        let store = CNContactStore()
                        let saveReq = CNSaveRequest()
                        for c in contacts {
                            if let mutable = try? c.mutableCopy() as? CNMutableContact {
                                saveReq.add(mutable, toContainerWithIdentifier: nil)
                            }
                        }
                        try store.execute(saveReq)
                        print("[Outcome] undo contacts imported \(contacts.count) items")
                    }
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
                print("[Outcome] ICS backup at \(bp). Import manually into calendar if needed.")
            }
        }
    }
}
