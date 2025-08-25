//
//  AnonymizerAV.swift
//  Anonymizer AV - production implementation (uses external LottieView.swift)
//

import SwiftUI
import Photos
import Contacts
import EventKit
import CryptoKit
import UniformTypeIdentifiers
import UIKit

struct Optimization: View {
    var body: some View {
        MainCardsView()
            .preferredColorScheme(.dark)
    }
}

// MARK: - Models

/// Category of duplicates
enum DuplicateBucket {
    case file(title: String, groups: [[URL]])         // each group is [URL]
    case media(title: String, groups: [[String]])    // groups of PHAsset localIdentifiers
    case contact(title: String, groups: [[CNContact]]) // groups of contacts
    case calendar(title: String, groups: [[EKEvent]])  // groups of events
}

/// Lightweight result summary
struct ScanSummary {
    var photosCount = 0
    var videosCount = 0
    var filesCount = 0
    var contactsCount = 0
    var calendarCount = 0
}

// MARK: - ScannerManager
/// Central manager coordinating scans. Uses async functions and supports cancellation via Task.
final class ScannerManager: ObservableObject {
    @Published var statusText: String = "Idle"
    @Published var progressText: String = ""
    @Published var isScanning: Bool = false

    @Published var buckets: [DuplicateBucket] = [] // aggregated results
    @Published var summary = ScanSummary()

    // internal cancellation task
    private var currentTask: Task<Void, Never>?

    // Throttle updates
    private var lastProgressUpdate: Date = .distantPast
    private let progressThrottleInterval: TimeInterval = 0.25

    // MARK: - Public API (Full / Focused scans)

    /// Start a full, multi-target sweep (images, videos, files, contacts, calendar).
    func startFullSweep() {
        stopScan()
        currentTask = Task {
            await MainActor.run { [weak self] in
                self?.isScanning = true
                self?.buckets.removeAll()
                self?.summary = ScanSummary()
                self?.statusText = "Preparing sweep..."
                self?.progressText = ""
            }

            await updateStatus("Scanning images...")
            do {
                // Photos (asset identifiers)
                let photoGroups = try await scanMediaAssets(of: .image)
                if Task.isCancelled { await finishEarly(); return }
                if !photoGroups.isEmpty {
                    await appendMediaBucket(title: "Image Duplicates", groups: photoGroups)
                }

                // Videos
                await updateStatus("Scanning videos...")
                let videoGroups = try await scanMediaAssets(of: .video)
                if Task.isCancelled { await finishEarly(); return }
                if !videoGroups.isEmpty {
                    await appendMediaBucket(title: "Video Duplicates", groups: videoGroups)
                }

                // Other files (app documents)
                await updateStatus("Scanning files...")
                let fileGroups = try await scanFilesFolder()
                if Task.isCancelled { await finishEarly(); return }
                if !fileGroups.isEmpty {
                    await appendFilesBucket(title: "Other Files Duplicates", groups: fileGroups)
                }

                // Contacts
                await updateStatus("Scanning contacts...")
                let contactGroups = try await scanContacts()
                if Task.isCancelled { await finishEarly(); return }
                if !contactGroups.isEmpty {
                    await appendContactsBucket(title: "Contacts Duplicates", groups: contactGroups)
                }

                // Calendar
                await updateStatus("Scanning calendar...")
                let eventGroups = try await scanCalendar()
                if Task.isCancelled { await finishEarly(); return }
                if !eventGroups.isEmpty {
                    await appendCalendarBucket(title: "Calendar Duplicates", groups: eventGroups)
                }

                await updateStatus("Scan complete")
            } catch {
                await updateStatus("Scan failed: \(error.localizedDescription)")
            }

            await MainActor.run { [weak self] in
                self?.isScanning = false
            }
        }
    }

    /// Start only a media sweep (images or videos). Uses same streaming/hash logic but focuses on one type.
    func startMediaSweep(of mediaType: PHAssetMediaType) {
        stopScan()
        currentTask = Task {
            await MainActor.run { [weak self] in
                self?.isScanning = true
                // don't clear other results — we append focused results
                self?.statusText = mediaType == .image ? "Preparing image scan..." : "Preparing video scan..."
                self?.progressText = ""
            }

            do {
                let groups = try await scanMediaAssets(of: mediaType)
                if Task.isCancelled { await finishEarly(); return }
                if !groups.isEmpty {
                    if mediaType == .image { await appendMediaBucket(title: "Image Duplicates", groups: groups) }
                    else { await appendMediaBucket(title: "Video Duplicates", groups: groups) }
                }
                await updateStatus("Scan complete")
            } catch {
                await updateStatus("Scan failed: \(error.localizedDescription)")
            }

            await MainActor.run { [weak self] in
                self?.isScanning = false
            }
        }
    }

    /// Start only file/document scan (app Documents folder)
    func startFilesSweep() {
        stopScan()
        currentTask = Task {
            await MainActor.run { [weak self] in
                self?.isScanning = true
                self?.statusText = "Preparing file scan..."
                self?.progressText = ""
            }

            do {
                let fileGroups = try await scanFilesFolder()
                if Task.isCancelled { await finishEarly(); return }
                if !fileGroups.isEmpty {
                    await appendFilesBucket(title: "Other Files Duplicates", groups: fileGroups)
                }
                await updateStatus("Scan complete")
            } catch {
                await updateStatus("Scan failed: \(error.localizedDescription)")
            }

            await MainActor.run { [weak self] in
                self?.isScanning = false
            }
        }
    }

    /// Start only contacts scan
    func startContactsSweep() {
        stopScan()
        currentTask = Task {
            await MainActor.run { [weak self] in
                self?.isScanning = true
                self?.statusText = "Preparing contacts scan..."
                self?.progressText = ""
            }

            do {
                let contactGroups = try await scanContacts()
                if Task.isCancelled { await finishEarly(); return }
                if !contactGroups.isEmpty {
                    await appendContactsBucket(title: "Contacts Duplicates", groups: contactGroups)
                }
                await updateStatus("Scan complete")
            } catch {
                await updateStatus("Scan failed: \(error.localizedDescription)")
            }

            await MainActor.run { [weak self] in
                self?.isScanning = false
            }
        }
    }

    /// Start only calendar scan
    func startCalendarSweep() {
        stopScan()
        currentTask = Task {
            await MainActor.run { [weak self] in
                self?.isScanning = true
                self?.statusText = "Preparing calendar scan..."
                self?.progressText = ""
            }

            do {
                let eventGroups = try await scanCalendar()
                if Task.isCancelled { await finishEarly(); return }
                if !eventGroups.isEmpty {
                    await appendCalendarBucket(title: "Calendar Duplicates", groups: eventGroups)
                }
                await updateStatus("Scan complete")
            } catch {
                await updateStatus("Scan failed: \(error.localizedDescription)")
            }

            await MainActor.run { [weak self] in
                self?.isScanning = false
            }
        }
    }

    func stopScan() {
        currentTask?.cancel()
        currentTask = nil
        Task { @MainActor in
            self.isScanning = false
            self.statusText = "Scan cancelled"
            self.progressText = ""
        }
    }

    // MARK: - Helper UI update methods
    @MainActor private func updateStatus(_ s: String) {
        statusText = s
        throttleProgressUpdate(s)
    }

    @MainActor private func throttleProgressUpdate(_ s: String) {
        let now = Date()
        if now.timeIntervalSince(lastProgressUpdate) > progressThrottleInterval {
            progressText = s
            lastProgressUpdate = now
        }
    }

    @MainActor private func finishEarly() {
        statusText = "Scan interrupted"
        isScanning = false
    }

    // Append buckets in a thread-safe way
    @MainActor private func appendFilesBucket(title: String, groups: [[URL]]) {
        print("[Scanner] appending file bucket '\(title)' groups: \(groups.count)")
        buckets.append(.file(title: title, groups: groups))
    }
    @MainActor private func appendMediaBucket(title: String, groups: [[String]]) {
        print("[Scanner] appending media bucket '\(title)' groups: \(groups.count)")
        buckets.append(.media(title: title, groups: groups))
    }
    @MainActor private func appendContactsBucket(title: String, groups: [[CNContact]]) {
        print("[Scanner] appending contact bucket '\(title)' groups: \(groups.count)")
        for (i,g) in groups.enumerated() {
            let names = g.map { "\($0.givenName) \($0.familyName) (id:\($0.identifier))" }
            print("[Scanner] contact group \(i): \(names)")
        }
        buckets.append(.contact(title: title, groups: groups))
    }
    @MainActor private func appendCalendarBucket(title: String, groups: [[EKEvent]]) {
        print("[Scanner] appending calendar bucket '\(title)' groups: \(groups.count)")
        buckets.append(.calendar(title: title, groups: groups))
    }

    // MARK: - Scanners

    /// Scans PhotoKit assets (image or video), computes SHA256 for each asset (streamed),
    /// and returns groups of duplicate asset-localIdentifiers.
    private func scanMediaAssets(of mediaType: PHAssetMediaType) async throws -> [[String]] {
        // Request photo library authorization first (handles .limited)
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            try await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in cont.resume(returning: ()) }
            }
        } else if status == .denied || status == .restricted {
            throw NSError(domain: "Scanner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Photo access denied"])
        }

        // Fetch assets
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let assets = PHAsset.fetchAssets(with: mediaType, options: fetchOptions)

        await MainActor.run {
            if mediaType == .image { self.summary.photosCount = assets.count }
            else if mediaType == .video { self.summary.videosCount = assets.count }
        }

        // Map: hash -> [localIdentifier]
        var map = [String: [String]]()

        // Process assets serially to reduce memory pressure
        let assetManager = PHAssetResourceManager.default()
        let resourceOptions = PHAssetResourceRequestOptions()
        resourceOptions.isNetworkAccessAllowed = true

        // Convert fetch result to array for async/await processing
        var assetList: [PHAsset] = []
        assets.enumerateObjects { a, _, _ in assetList.append(a) }

        for asset in assetList {
            if Task.isCancelled { break }
            await updateStatus("Processing asset...")
            // Get the primary resource (original)
            guard let resource = PHAssetResource.assetResources(for: asset).first else { continue }
            // Request data incrementally and compute SHA256
            let hash = try await sha256ForAssetResource(resource: resource, assetManager: assetManager, options: resourceOptions)
            if Task.isCancelled { break }
            // Map by hash using asset.localIdentifier (we use identifier to allow delete via PH)
            map[hash, default: []].append(asset.localIdentifier)
            await updateStatus("Scanned asset")
        }

        // Build groups with size >= 2
        let groups = map.values.filter { $0.count >= 2 }
        return groups
    }

    /// Asks the asset manager to stream data and computes SHA256 incrementally
    private func sha256ForAssetResource(resource: PHAssetResource,
                                        assetManager: PHAssetResourceManager,
                                        options: PHAssetResourceRequestOptions) async throws -> String {
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            var hasher = SHA256()
            assetManager.requestData(for: resource, options: options, dataReceivedHandler: { data in
                data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
                    hasher.update(data: ptr.bindMemory(to: UInt8.self))
                }
            }, completionHandler: { error in
                if let err = error { cont.resume(throwing: err); return }
                let digest = hasher.finalize()
                let hex = digest.map { String(format: "%02x", $0) }.joined()
                cont.resume(returning: hex)
            })
        }
    }

    /// Writes asset to a temp file (small representation). Used only for UI display and grouping.
    private func writeAssetToTempFile(resource: PHAssetResource,
                                      assetManager: PHAssetResourceManager,
                                      options: PHAssetResourceRequestOptions) async throws -> URL? {
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL?, Error>) in
            let tmpDir = FileManager.default.temporaryDirectory
            let filename = UUID().uuidString + "-" + (resource.originalFilename)
            let tmpURL = tmpDir.appendingPathComponent(filename)
            guard let outStream = OutputStream(url: tmpURL, append: false) else {
                cont.resume(returning: nil)
                return
            }
            outStream.open()
            assetManager.requestData(for: resource, options: options, dataReceivedHandler: { data in
                let bytes = [UInt8](data)
                _ = outStream.write(bytes, maxLength: bytes.count)
            }, completionHandler: { error in
                outStream.close()
                if let err = error { cont.resume(throwing: err); return }
                cont.resume(returning: tmpURL)
            })
        }
    }

    /// Scan files in app Documents directory and compute SHA256 groups
    private func scanFilesFolder() async throws -> [[URL]] {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        var map = [String: [URL]]()
        var counter = 0

        guard let enumerator = fm.enumerator(at: docs, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }

        for case let fileURL as URL in enumerator {
            if Task.isCancelled { break }
            // Check regular file
            let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
            if resourceValues?.isRegularFile != true { continue }
            counter += 1
            if counter % 50 == 0 { await updateStatus("Scanned \(counter) files") }
            // Stream-hash
            if let hash = try? await sha256ForLocalFile(fileURL) {
                map[hash, default: []].append(fileURL)
            }
        }

        await MainActor.run { self.summary.filesCount = counter }
        let groups = map.values.filter { $0.count >= 2 }
        return groups
    }

    /// Stream SHA256 for local file using FileHandle
    private func sha256ForLocalFile(_ url: URL) async throws -> String {
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            Task {
                do {
                    let fh = try FileHandle(forReadingFrom: url)
                    var hasher = SHA256()
                    while true {
                        if Task.isCancelled {
                            try? fh.close()
                            cont.resume(throwing: CancellationError())
                            return
                        }
                        let data = try fh.read(upToCount: 64 * 1024)
                        if let d = data, !d.isEmpty {
                            d.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
                                hasher.update(data: ptr.bindMemory(to: UInt8.self))
                            }
                        } else {
                            try? fh.close()
                            let digest = hasher.finalize()
                            let hex = digest.map { String(format: "%02x", $0) }.joined()
                            cont.resume(returning: hex)
                            return
                        }
                    }
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Contact helper normalizers
    private func normalizePhone(_ raw: String) -> String {
        let digits = raw.filter { $0.isNumber }
        // keep last up to 11 digits (heuristic) to handle country codes
        return String(digits.suffix(11))
    }

    private func normalizeEmail(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: - Contacts scanning
    /// Scan contacts and group duplicates by normalized name or shared phone/email
    private func scanContacts() async throws -> [[CNContact]] {
        let store = CNContactStore()
        // Request access
        try await requestContactsAccessIfNeeded(store: store)

        // Fetch contacts with relevant keys
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey, CNContactEmailAddressesKey, CNContactIdentifierKey] as [CNKeyDescriptor]
        var contacts: [CNContact] = []
        let req = CNContactFetchRequest(keysToFetch: keys)
        try store.enumerateContacts(with: req) { contact, _ in
            contacts.append(contact)
        }

        await MainActor.run { self.summary.contactsCount = contacts.count }

        // union-find grouping by phone/email/name to handle transitive links
        var parent = Array(0..<contacts.count)
        func find(_ x: Int) -> Int {
            var x = x
            while parent[x] != x { parent[x] = parent[parent[x]]; x = parent[x] }
            return x
        }
        func unite(_ a: Int, _ b: Int) {
            let ra = find(a), rb = find(b); if ra != rb { parent[rb] = ra }
        }

        var phoneMap = [String: Int]()
        var emailMap = [String: Int]()
        var nameMap = [String: Int]()

        for (i, c) in contacts.enumerated() {
            // normalized name
            let full = (c.givenName + " " + c.familyName).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !full.isEmpty {
                if let j = nameMap[full] { unite(i, j) }
                else { nameMap[full] = i }
            }

            for pn in c.phoneNumbers {
                let raw = pn.value.stringValue
                let norm = normalizePhone(raw)
                if norm.isEmpty { continue }
                if let j = phoneMap[norm] { unite(i, j) }
                else { phoneMap[norm] = i }
            }

            for em in c.emailAddresses {
                let raw = String(em.value)
                let norm = normalizeEmail(raw)
                if norm.isEmpty { continue }
                if let j = emailMap[norm] { unite(i, j) }
                else { emailMap[norm] = i }
            }
        }

        var groupsMap = [Int: [CNContact]]()
        for i in 0..<contacts.count {
            let r = find(i)
            groupsMap[r, default: []].append(contacts[i])
        }

        let resultGroups = groupsMap.values.filter { $0.count >= 2 }
        return resultGroups
    }

    /// Request contacts access (async)
    private func requestContactsAccessIfNeeded(store: CNContactStore) async throws {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if status == .notDetermined {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                store.requestAccess(for: .contacts) { granted, error in
                    if let e = error { cont.resume(throwing: e); return }
                    if granted { cont.resume(returning: ()) }
                    else {
                        cont.resume(throwing: NSError(domain: "Scanner", code: 2, userInfo: [NSLocalizedDescriptionKey: "Contacts permission denied"]))
                    }
                }
            }
        } else if status == .denied || status == .restricted {
            throw NSError(domain: "Scanner", code: 2, userInfo: [NSLocalizedDescriptionKey: "Contacts permission denied"])
        }
    }

    /// Merge contacts: keep base contact, copy missing phones/emails and delete duplicates.
    /// This is executed on-demand by the UI; keeping it here for reuse.
    func mergeContacts(base: CNContact, duplicates: [CNContact]) async throws {
        // NOTE: create a fresh CNContactStore per attempt to avoid stale/invalid XPC connections.
        var lastError: Error?
        for attempt in 1...2 {
            do {
                let store = CNContactStore()
                try await requestContactsAccessIfNeeded(store: store)
                try performMergeSync(store: store, base: base, duplicates: duplicates)
                print("[Scanner] mergeContacts succeeded on attempt \(attempt) for base \(base.identifier)")
                return
            } catch {
                lastError = error
                let msg = (error as NSError).localizedDescription
                print("[Scanner] merge attempt \(attempt) failed: \(msg)")
                if msg.contains("XPC connection was invalidated") && attempt == 1 {
                    // small delay then retry with a fresh store
                    try await Task.sleep(nanoseconds: 200_000_000) // 200ms
                    continue
                } else {
                    throw error
                }
            }
        }
        throw lastError ?? NSError(domain: "Scanner", code: 5, userInfo: [NSLocalizedDescriptionKey: "Merge failed"])
    }

    /// The synchronous core merge logic (throws)
    private func performMergeSync(store: CNContactStore, base: CNContact, duplicates: [CNContact]) throws {
        // Fetch the up-to-date mutable base from store if possible
        let keys: [CNKeyDescriptor] = [CNContactPhoneNumbersKey, CNContactEmailAddressesKey, CNContactGivenNameKey, CNContactFamilyNameKey, CNContactIdentifierKey] as [CNKeyDescriptor]
        guard let fetchedBase = try? store.unifiedContact(withIdentifier: base.identifier, keysToFetch: keys) else {
            throw NSError(domain: "Scanner", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unable to fetch base contact from store"])
        }
        guard let mutableBase = try? fetchedBase.mutableCopy() as? CNMutableContact else {
            throw NSError(domain: "Scanner", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unable to mutate base contact"])
        }

        // Collect existing phones/emails to avoid duplicates (normalized)
        func normalizePhone(_ raw: String) -> String { String(raw.filter { $0.isNumber }.suffix(11)) }
        func normalizeEmail(_ raw: String) -> String { raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

        var existingPhones = Set<String>(mutableBase.phoneNumbers.map { normalizePhone($0.value.stringValue) })
        var existingEmails = Set<String>(mutableBase.emailAddresses.map { normalizeEmail(String($0.value)) })

        // Build save request
        let saveReq = CNSaveRequest()
        for dup in duplicates {
            if dup.identifier == base.identifier { continue }
            // Copy phones
            for phone in dup.phoneNumbers {
                let raw = phone.value.stringValue
                let num = normalizePhone(raw)
                if num.isEmpty { continue }
                if existingPhones.contains(num) { continue }
                // append original labeled value
                mutableBase.phoneNumbers.append(phone)
                existingPhones.insert(num)
            }
            // Copy emails
            for email in dup.emailAddresses {
                let raw = String(email.value)
                let em = normalizeEmail(raw)
                if em.isEmpty { continue }
                if existingEmails.contains(em) { continue }
                mutableBase.emailAddresses.append(email)
                existingEmails.insert(em)
            }
            // Delete duplicate contact (fetch latest mutable if possible)
            if let dupFetched = try? store.unifiedContact(withIdentifier: dup.identifier, keysToFetch: [CNContactIdentifierKey] as [CNKeyDescriptor]),
               let dupMutable = try? dupFetched.mutableCopy() as? CNMutableContact {
                saveReq.delete(dupMutable)
            } else if let dupMutable = try? dup.mutableCopy() as? CNMutableContact {
                saveReq.delete(dupMutable)
            }
        }
        // Update base
        saveReq.update(mutableBase)
        try store.execute(saveReq)
    }

    /// Delete contacts (by CNContact)
    func deleteContacts(_ contacts: [CNContact]) async throws {
        let store = CNContactStore()
        try await requestContactsAccessIfNeeded(store: store)
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

    /// Scan calendar events for duplicates by title + startDate (1 year window)
    private func scanCalendar() async throws -> [[EKEvent]] {
        let store = EKEventStore()
        // Request access
        try await requestCalendarAccessIfNeeded(store: store)

        let calendars = store.calendars(for: .event)
        let now = Date()
        let oneYear = Calendar.current.date(byAdding: .year, value: 1, to: now)!
        let predicate = store.predicateForEvents(withStart: now, end: oneYear, calendars: calendars)
        let events = store.events(matching: predicate)
        await MainActor.run { self.summary.calendarCount = events.count }

        // Group by title + start date (rounded to minute to be a bit more tolerant)
        var map = [String: [EKEvent]]()
        for e in events {
            guard let title = e.title, !title.isEmpty else { continue }
            // round start date to minute
            let rounded = Int(e.startDate.timeIntervalSince1970 / 60)
            let key = "\(title) | \(rounded)"
            map[key, default: []].append(e)
        }

        let groups = map.values.filter { $0.count >= 2 }
        return groups
    }

    private func requestCalendarAccessIfNeeded(store: EKEventStore) async throws {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .notDetermined {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                store.requestAccess(to: .event) { granted, error in
                    if let e = error { cont.resume(throwing: e); return }
                    if granted { cont.resume(returning: ()) }
                    else {
                        cont.resume(throwing: NSError(domain: "Scanner", code: 4, userInfo: [NSLocalizedDescriptionKey: "Calendar permission denied"]))
                    }
                }
            }
        } else if status == .denied || status == .restricted {
            throw NSError(domain: "Scanner", code: 4, userInfo: [NSLocalizedDescriptionKey: "Calendar permission denied"])
        }
    }

    /// Delete calendar events
    func deleteCalendarEvents(_ events: [EKEvent]) async throws {
        let store = EKEventStore()
        try await requestCalendarAccessIfNeeded(store: store)
        for e in events {
            if Task.isCancelled { break }
            try store.remove(e, span: .futureEvents, commit: false)
        }
        try store.commit()
    }
}

// MARK: - MainCardsView (main UI)
struct MainCardsView: View {
    @StateObject private var scanner = ScannerManager()
    @State private var showResultsSheet = false
    @State private var selectedBucketIndex: Int? = nil

    // undo toast state
    @State private var lastActionRecord: ActionRecord? = nil
    @State private var showUndoToast: Bool = false

    // error alert state
    @State private var showErrorAlert: Bool = false
    @State private var alertMessage: String = ""

    private let cardCorner: CGFloat = 16

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 12) {
                    header
                    card(title: "Photos", subtitle: "\(scanner.summary.photosCount) items", iconName: "photo.on.rectangle", tint: .blue) {
                        // trigger focused image-only scan
                        scanner.startMediaSweep(of: .image)
                    }

                    card(title: "Videos", subtitle: "\(scanner.summary.videosCount) items", iconName: "film", tint: .pink) {
                        // trigger focused video-only scan
                        scanner.startMediaSweep(of: .video)
                    }

                    card(title: "Contacts", subtitle: "\(scanner.summary.contactsCount) contacts", iconName: "person.2.fill", tint: .teal) {
                        // trigger focused contacts scan
                        scanner.startContactsSweep()
                    }

                    card(title: "Calendar", subtitle: "\(scanner.summary.calendarCount) events", iconName: "calendar", tint: .green) {
                        // trigger focused calendar scan
                        scanner.startCalendarSweep()
                    }

                    card(title: "Other Files", subtitle: "\(scanner.summary.filesCount) files", iconName: "doc.fill", tint: .yellow) {
                        // trigger focused files scan
                        scanner.startFilesSweep()
                    }

                    card(title: "Full Sweep", subtitle: "Comprehensive device scan (subject to iOS limits)", iconName: "shield.lefthalf.fill", tint: .purple) {
                        scanner.startFullSweep()
                    }

                    Spacer(minLength: 48)
                }
                .padding(16)
            }
            .background(Color(UIColor.systemBackground))
            .edgesIgnoringSafeArea(.all)

            // Scan overlay
            if scanner.isScanning {
                Color.black.opacity(0.6).edgesIgnoringSafeArea(.all)
                VStack(spacing: 16) {
                    // Use your existing LottieView.swift
                    LottieView(name: "radar_scan", loopMode: .loop, speed: 1.5, play: scanner.isScanning)
                        .frame(width: 200, height: 200)
                    Text(scanner.statusText)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                    Text(scanner.progressText)
                        .font(.system(size: 14))
                        .foregroundColor(.gray)

                    Button(action: { scanner.stopScan() }) {
                        Text("Cancel Scan")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.clear)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.blue, lineWidth: 1))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 24)
                }
                .padding(24)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(16)
                .padding(24)
                .transition(.opacity)
            }

            // Results button
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    if !scanner.buckets.isEmpty {
                        Button(action: { showResultsSheet = true }) {
                            Image(systemName: "list.bullet")
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .clipShape(Circle())
                                .shadow(radius: 8)
                        }
                        .padding()
                    }
                }
            }

            // Undo toast
            if let rec = lastActionRecord, showUndoToast {
                VStack {
                    Spacer()
                    HStack {
                        Text(rec.summary).foregroundColor(.white)
                        Spacer()
                        Button("Undo") {
                            Task {
                                do {
                                    try await OutcomeHandler.shared.undo(rec)
                                    OutcomeHandler.shared.removeRecord(id: rec.id)
                                    lastActionRecord = nil
                                    showUndoToast = false
                                } catch {
                                    print("Undo failed: \(error)")
                                    alertMessage = "Undo failed: \(error.localizedDescription)"
                                    showErrorAlert = true
                                }
                            }
                        }
                        .foregroundColor(.white)
                    }
                    .padding()
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(12)
                    .padding()
                }
                .transition(.move(edge: .bottom))
                .animation(.easeInOut, value: showUndoToast)
            }
        }
        .sheet(isPresented: $showResultsSheet) {
            ResultsListView(onAction: { action, bucketIndex, groupIndex in
                // Process actions (Delete / Merge) here
                Task {
                    await handleResultAction(action: action, bucketIndex: bucketIndex, groupIndex: groupIndex)
                }
            })
            .environmentObject(scanner)
        }
        .environmentObject(scanner)
        .alert(isPresented: $showErrorAlert) {
            Alert(title: Text("Error"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
    }

    // MARK: - UI building helpers
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("File Manager")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
            Text("Manage and organize your files")
                .foregroundColor(.gray)
                .font(.subheadline)
        }
        .padding(.bottom, 12)
    }

    private func card(title: String, subtitle: String, iconName: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: iconName)
                    .resizable()
                    .frame(width: 44, height: 44)
                    .foregroundColor(tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline).foregroundColor(.white)
                    Text(subtitle).font(.subheadline).foregroundColor(.gray)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
            }
            .padding(16)
            .background(Color(UIColor.systemGray6))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(UIColor.systemGray4), lineWidth: 1))
        }
    }

    // MARK: - Actions for Results
    private func handleResultAction(action: ResultsAction, bucketIndex: Int, groupIndex: Int) async {
        print("[UI] handleResultAction START action=\(action) bucket=\(bucketIndex) group=\(groupIndex)")
        defer { print("[UI] handleResultAction   END action=\(action) bucket=\(bucketIndex) group=\(groupIndex)") }

        // defensive: re-check bounds on main actor before acting
        await MainActor.run {
            guard bucketIndex < scanner.buckets.count else { return }
        }

        let bucket = await MainActor.run { scanner.buckets.indices.contains(bucketIndex) ? scanner.buckets[bucketIndex] : nil }
        guard let bucketUnwrapped = bucket else { return }

        switch (bucketUnwrapped, action) {
        case (.file(_, let groups), .deleteAll):
            guard groups.indices.contains(groupIndex) else { return }
            let urls = groups[groupIndex]
            do {
                // backup & delete via OutcomeHandler
                print("[UI] committing delete files for \(urls.count) files")
                let rec = try await OutcomeHandler.shared.commitDeleteFiles(urls)
                // keep for undo toast
                lastActionRecord = rec
                showUndoToast = true
                // update UI: remove group
                await MainActor.run {
                    guard bucketIndex < scanner.buckets.count else { return }
                    var newBuckets = scanner.buckets
                    if case .file(let title, var g) = newBuckets[bucketIndex] {
                        if g.indices.contains(groupIndex) {
                            g.remove(at: groupIndex)
                            if g.isEmpty { newBuckets.remove(at: bucketIndex) }
                            else { newBuckets[bucketIndex] = .file(title: title, groups: g) }
                            scanner.buckets = newBuckets
                        }
                    }
                }
            } catch {
                print("[Outcome] delete files failed: \(error)")
                await MainActor.run {
                    alertMessage = "Failed to delete files: \(error.localizedDescription)"
                    showErrorAlert = true
                }
            }

        case (.media(_, let idGroups), .deleteAll):
            guard idGroups.indices.contains(groupIndex) else { return }
            let ids = idGroups[groupIndex]
            do {
                print("[UI] committing delete media for \(ids.count) assets")
                let rec = try await OutcomeHandler.shared.commitDeleteMedia(localIdentifiers: ids)
                lastActionRecord = rec
                showUndoToast = true
                // update UI: remove group
                await MainActor.run {
                    guard bucketIndex < scanner.buckets.count else { return }
                    var newBuckets = scanner.buckets
                    if case .media(let title, var g) = newBuckets[bucketIndex] {
                        if g.indices.contains(groupIndex) {
                            g.remove(at: groupIndex)
                            if g.isEmpty { newBuckets.remove(at: bucketIndex) }
                            else { newBuckets[bucketIndex] = .media(title: title, groups: g) }
                            scanner.buckets = newBuckets
                        }
                    }
                }
            } catch {
                print("[Outcome] delete media failed: \(error)")
                await MainActor.run {
                    alertMessage = "Failed to delete media: \(error.localizedDescription)"
                    showErrorAlert = true
                }
            }

        case (.contact(_, let contactGroups), .merge):
            guard contactGroups.indices.contains(groupIndex) else { return }
            let contacts = contactGroups[groupIndex]
            // choose best base
            let base = contacts.max { (a, b) -> Bool in
                (a.phoneNumbers.count + a.emailAddresses.count) < (b.phoneNumbers.count + b.emailAddresses.count)
            } ?? contacts.first!
            let duplicates = contacts.filter { $0.identifier != base.identifier }

            // create backup + commit merge via OutcomeHandler
            do {
                print("[UI] committing merge for base \(base.identifier) duplicates: \(duplicates.map{$0.identifier})")
                let rec = try await OutcomeHandler.shared.commitMergeContacts(base: base, duplicates: duplicates)
                lastActionRecord = rec
                showUndoToast = true
                // update UI: remove group
                await MainActor.run {
                    guard bucketIndex < scanner.buckets.count else { return }
                    var newBuckets = scanner.buckets
                    if case .contact(let title, var g) = newBuckets[bucketIndex] {
                        if g.indices.contains(groupIndex) {
                            g.remove(at: groupIndex)
                            if g.isEmpty { newBuckets.remove(at: bucketIndex) }
                            else { newBuckets[bucketIndex] = .contact(title: title, groups: g) }
                            scanner.buckets = newBuckets
                        }
                    }
                }
            } catch {
                print("[Outcome] merge contacts failed: \(error)")
                await MainActor.run {
                    alertMessage = "Failed to merge contacts: \(error.localizedDescription)"
                    showErrorAlert = true
                }
            }

        case (.contact(_, let contactGroups), .deleteAll):
            guard contactGroups.indices.contains(groupIndex) else { return }
            let contacts = contactGroups[groupIndex]
            do {
                // backup contacts first
                print("[UI] backing up contacts prior to delete: \(contacts.count)")
                let backupRec = try await OutcomeHandler.shared.backupContacts(contacts)
                // then delete from store
                try await scanner.deleteContacts(contacts)
                // log deletion record (so undo can import vCard)
                let rec = ActionRecord(id: UUID(), type: .contacts, kind: .delete, timestamp: Date(), summary: "Deleted \(contacts.count) contacts", payload: ["backupPath": backupRec.payload["backupPath"] ?? ""], itemsPreview: contacts.prefix(6).map { "\($0.givenName) \($0.familyName)" })
                OutcomeHandler.shared.saveRecord(rec)

                lastActionRecord = rec
                showUndoToast = true

                await MainActor.run {
                    guard bucketIndex < scanner.buckets.count else { return }
                    var newBuckets = scanner.buckets
                    if case .contact(let title, var g) = newBuckets[bucketIndex] {
                        if g.indices.contains(groupIndex) {
                            g.remove(at: groupIndex)
                            if g.isEmpty { newBuckets.remove(at: bucketIndex) }
                            else { newBuckets[bucketIndex] = .contact(title: title, groups: g) }
                            scanner.buckets = newBuckets
                        }
                    }
                }
            } catch {
                print("[Outcome] delete contacts failed: \(error)")
                await MainActor.run {
                    alertMessage = "Failed to delete contacts: \(error.localizedDescription)"
                    showErrorAlert = true
                }
            }

        case (.calendar(_, let eventGroups), .deleteAll):
            guard eventGroups.indices.contains(groupIndex) else { return }
            let events = eventGroups[groupIndex]
            do {
                print("[UI] committing delete calendar events count=\(events.count)")
                let rec = try await OutcomeHandler.shared.commitDeleteCalendarEvents(events)
                lastActionRecord = rec
                showUndoToast = true

                // update UI similar to above
                await MainActor.run {
                    guard bucketIndex < scanner.buckets.count else { return }
                    var newBuckets = scanner.buckets
                    if case .calendar(let title, var g) = newBuckets[bucketIndex] {
                        if g.indices.contains(groupIndex) {
                            g.remove(at: groupIndex)
                            if g.isEmpty { newBuckets.remove(at: bucketIndex) }
                            else { newBuckets[bucketIndex] = .calendar(title: title, groups: g) }
                            scanner.buckets = newBuckets
                        }
                    }
                }
            } catch {
                print("[Outcome] delete events failed: \(error)")
                await MainActor.run {
                    alertMessage = "Failed to delete events: \(error.localizedDescription)"
                    showErrorAlert = true
                }
            }

        default:
            break
        }
    }
}

// MARK: - ResultsListView (sheet)
enum ResultsAction {
    case deleteAll
    case merge
}

struct ResultsListView: View {
    @EnvironmentObject var scanner: ScannerManager   // live updates
    var onAction: (ResultsAction, Int, Int) -> Void

    @Environment(\.presentationMode) var presentation

    var body: some View {
        NavigationView {
            List {
                ForEach(Array(scanner.buckets.enumerated()), id: \.offset) { idx, bucket in
                    Section(header: Text(bucketTitle(bucket))) {
                        switch bucket {
                        case .file(_, let groups):
                            ForEach(Array(groups.enumerated()), id: \.offset) { gidx, group in
                                HStack {
                                    NavigationLink(destination: FileGroupDetailView(group: group)) {
                                        Text("Group \(gidx + 1) (\(group.count) files)")
                                    }
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { onAction(.deleteAll, idx, gidx) } label: { Label("Delete", systemImage: "trash") }
                                }
                            }
                        case .media(_, let groups):
                            ForEach(Array(groups.enumerated()), id: \.offset) { gidx, group in
                                HStack {
                                    NavigationLink(destination: MediaGroupDetailView(localIdentifiers: group)) {
                                        Text("Group \(gidx + 1) (\(group.count) items)")
                                    }
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { onAction(.deleteAll, idx, gidx) } label: { Label("Delete", systemImage: "trash") }
                                }
                            }
                        case .contact(_, let groups):
                            ForEach(Array(groups.enumerated()), id: \.offset) { gidx, group in
                                HStack {
                                    NavigationLink(destination: ContactGroupDetailView(group: group)) {
                                        Text("Group \(gidx + 1) (\(group.count) contacts)")
                                    }
                                }
                                .swipeActions(edge: .trailing) {
                                    Button { onAction(.merge, idx, gidx) } label: { Label("Merge", systemImage: "person.fill.checkmark") }.tint(.blue)
                                    Button(role: .destructive) { onAction(.deleteAll, idx, gidx) } label: { Label("Delete", systemImage: "trash") }
                                }
                            }
                        case .calendar(_, let groups):
                            ForEach(Array(groups.enumerated()), id: \.offset) { gidx, group in
                                HStack {
                                    NavigationLink(destination: CalendarGroupDetailView(group: group)) {
                                        Text("Group \(gidx + 1) (\(group.count) events)")
                                    }
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { onAction(.deleteAll, idx, gidx) } label: { Label("Delete", systemImage: "trash") }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(GroupedListStyle())
            .navigationBarTitle("Scan Results", displayMode: .inline)
            .navigationBarItems(trailing: Button("Done") {
                presentation.wrappedValue.dismiss()
            })
        }
    }

    private func bucketTitle(_ b: DuplicateBucket) -> String {
        switch b {
        case .file(let title, _): return title
        case .media(let title, _): return title
        case .contact(let title, _): return title
        case .calendar(let title, _): return title
        }
    }
}

// MARK: - Detail Views

struct FileGroupDetailView: View {
    let group: [URL]
    var body: some View {
        List {
            ForEach(group, id: \.self) { url in
                HStack {
                    Image(systemName: "doc")
                    Text(url.lastPathComponent)
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0, countStyle: .file))
                        .foregroundColor(.gray)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Duplicate Files")
    }
}

struct MediaGroupDetailView: View {
    let localIdentifiers: [String]
    var body: some View {
        List {
            ForEach(localIdentifiers, id: \.self) { id in
                HStack(alignment: .center, spacing: 12) {
                    AssetThumbnailView(localIdentifier: id)
                        .frame(width: 80, height: 80)
                        .cornerRadius(8)
                    VStack(alignment: .leading) {
                        Text(id).font(.caption).lineLimit(1)
                        Text("Tap to open in Photos").font(.caption2).foregroundColor(.gray)
                    }
                    Spacer()
                    Button(action: {
                        // open Photos app (best-effort). There's no public URL scheme to open a specific asset reliably.
                        if let url = URL(string: "photos-redirect://") {
                            UIApplication.shared.open(url, options: [:], completionHandler: nil)
                        }
                    }) {
                        Image(systemName: "arrow.up.right.square")
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .navigationTitle("Duplicate Media")
    }
}

struct AssetThumbnailView: View {
    let localIdentifier: String
    @State private var image: UIImage? = nil

    var body: some View {
        Group {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().foregroundColor(Color(UIColor.systemGray5))
            }
        }
        .onAppear { load() }
    }

    private func load() {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        let target = CGSize(width: 240, height: 240)
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = assets.firstObject else { return }
        PHImageManager.default().requestImage(for: asset, targetSize: target, contentMode: .aspectFill, options: options) { img, _ in
            if let img = img { self.image = img }
        }
    }
}

struct ContactGroupDetailView: View {
    let group: [CNContact]
    var body: some View {
        List {
            ForEach(group, id: \.identifier) { c in
                VStack(alignment: .leading) {
                    Text("\(c.givenName) \(c.familyName)").font(.headline)
                    if !c.phoneNumbers.isEmpty {
                        ForEach(Array(c.phoneNumbers.enumerated()), id: \.offset) { _, pn in
                            Text(pn.value.stringValue).font(.subheadline)
                        }
                    }
                    if !c.emailAddresses.isEmpty {
                        ForEach(Array(c.emailAddresses.enumerated()), id: \.offset) { _, em in
                            Text(String(em.value)).font(.subheadline)
                        }
                    }
                }
            }
        }
        .navigationTitle("Duplicates")
    }
}

struct CalendarGroupDetailView: View {
    let group: [EKEvent]
    var body: some View {
        List {
            ForEach(group, id: \.eventIdentifier) { e in
                VStack(alignment: .leading) {
                    Text(e.title ?? "Untitled").font(.headline)
                    Text(e.startDate, style: .date).font(.subheadline)
                }
            }
        }
        .navigationTitle("Duplicate Events")
    }
}
