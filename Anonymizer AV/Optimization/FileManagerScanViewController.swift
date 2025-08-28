//  AnonymizerAV.swift
//  Anonymizer AV - calendar duplicate handling (UI: locate only, no delete/merge)
//

import SwiftUI
import Photos
import Contacts
import EventKit
import CryptoKit
import UniformTypeIdentifiers
import UIKit
import Combine
import ContactsUI

// Quick helper view used by your router
struct Optimization: View {
    var body: some View {
        // Presents the main scanner UI in dark mode by default
        MainCardsView()
            .preferredColorScheme(.dark)
    }
}

// MARK: - Errors

enum ScannerError: Error, LocalizedError {
    case photoAccessDenied
    case contactsAccessDenied
    case calendarAccessDenied
    case mergeFailed(String)
    case generic(String)

    var errorDescription: String? {
        switch self {
        case .photoAccessDenied: return "Photo access denied"
        case .contactsAccessDenied: return "Contacts permission denied"
        case .calendarAccessDenied: return "Calendar permission denied"
        case .mergeFailed(let msg): return "Merge failed: \(msg)"
        case .generic(let msg): return msg
        }
    }
}

// MARK: - Models

enum DuplicateBucket {
    case media(title: String, groups: [[String]])
    case contact(title: String, groups: [[CNContact]])
    case calendar(title: String, groups: [[EKEvent]])
}

struct ScanSummary {
    var photosCount = 0
    var videosCount = 0
    var contactsCount = 0
    var calendarCount = 0
}

// MARK: - ScannerManager
final class ScannerManager: ObservableObject {
    @Published var statusText: String = "Idle"
    @Published var progressText: String = ""
    @Published var isScanning: Bool = false

    @Published var buckets: [DuplicateBucket] = []
    @Published var summary = ScanSummary()

    @Published var scanFinishedWithNoDuplicates: Bool = false

    private var currentTask: Task<Void, Never>?
    private var lastProgressUpdate: Date = .distantPast
    private let progressThrottleInterval: TimeInterval = 0.25

    // -------------------
    // FOCUSED SCANS ONLY
    // -------------------
    func startMediaSweep(of mediaType: PHAssetMediaType) {
        stopScan()
        scanFinishedWithNoDuplicates = false

        currentTask = Task { [weak self] in
            await MainActor.run {
                guard let self = self else { return }
                // clear all previous buckets to ensure fresh results
                self.buckets.removeAll()
                self.isScanning = true
                self.statusText = mediaType == .image ? "Preparing image scan..." : "Preparing video scan..."
                self.progressText = ""
            }

            do {
                let groups = try await self?.scanMediaAssets(of: mediaType) ?? []
                if Task.isCancelled { await self?.finishEarly(); return }
                if mediaType == .image { await self?.handleAppendOrRemoveMedia(title: "Image Duplicates", groups: groups, removeIfEmpty: true) }
                else { await self?.handleAppendOrRemoveMedia(title: "Video Duplicates", groups: groups, removeIfEmpty: true) }
                await self?.updateStatus("Scan complete")
            } catch {
                await self?.updateStatus("Scan failed: \(error.localizedDescription)")
            }

            await MainActor.run {
                self?.isScanning = false
                if let self = self {
                    let exists = self.buckets.contains { b in
                        switch b {
                        case .media(let t, let g):
                            if mediaType == .image && t == "Image Duplicates" { return !g.isEmpty }
                            if mediaType == .video && t == "Video Duplicates" { return !g.isEmpty }
                            return false
                        default: return false
                        }
                    }
                    self.scanFinishedWithNoDuplicates = !exists
                }
            }
        }
    }

    func startContactsSweep() {
        stopScan()
        scanFinishedWithNoDuplicates = false

        currentTask = Task { [weak self] in
            await MainActor.run {
                guard let self = self else { return }
                // clear all previous buckets to ensure fresh results
                self.buckets.removeAll()
                self.isScanning = true
                self.statusText = "Preparing contacts scan..."
                self.progressText = ""
            }

            do {
                let contactGroups = try await self?.scanContacts() ?? []
                if Task.isCancelled { await self?.finishEarly(); return }
                await self?.handleAppendOrRemoveContacts(title: "Contacts Duplicates", groups: contactGroups, removeIfEmpty: true)
                await self?.updateStatus("Scan complete")
            } catch {
                await self?.updateStatus("Scan failed: \(error.localizedDescription)")
            }

            await MainActor.run {
                self?.isScanning = false
                if let self = self {
                    let exists = self.buckets.contains { b in
                        if case .contact(let t, let g) = b { return t == "Contacts Duplicates" && !g.isEmpty }
                        return false
                    }
                    self.scanFinishedWithNoDuplicates = !exists
                }
            }
        }
    }

    func startCalendarSweep() {
        stopScan()
        scanFinishedWithNoDuplicates = false

        currentTask = Task { [weak self] in
            await MainActor.run {
                guard let self = self else { return }
                // clear all previous buckets to ensure fresh results
                self.buckets.removeAll()
                self.isScanning = true
                self.statusText = "Preparing calendar scan..."
                self.progressText = ""
            }

            do {
                let eventGroups = try await self?.scanCalendar() ?? []
                if Task.isCancelled { await self?.finishEarly(); return }
                await self?.handleAppendOrRemoveCalendar(title: "Calendar Duplicates", groups: eventGroups, removeIfEmpty: true)
                await self?.updateStatus("Scan complete")
            } catch {
                await self?.updateStatus("Scan failed: \(error.localizedDescription)")
            }

            await MainActor.run {
                self?.isScanning = false
                if let self = self {
                    let exists = self.buckets.contains { b in
                        if case .calendar(let t, let g) = b { return t == "Calendar Duplicates" && !g.isEmpty }
                        return false
                    }
                    self.scanFinishedWithNoDuplicates = !exists
                }
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
            self.scanFinishedWithNoDuplicates = false
        }
    }

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

    // Safe upsert helpers (media/contact/calendar)
    @MainActor private func handleAppendOrRemoveMedia(title: String, groups: [[String]], removeIfEmpty: Bool = true) {
        if groups.isEmpty {
            if removeIfEmpty {
                buckets.removeAll { b in
                    if case .media(let t, _) = b { return t == title }
                    return false
                }
            }
            return
        }
        if let idx = buckets.firstIndex(where: { b in
            if case .media(let t, _) = b { return t == title }
            return false
        }) {
            buckets[idx] = .media(title: title, groups: groups)
        } else {
            buckets.append(.media(title: title, groups: groups))
        }
    }

    @MainActor private func handleAppendOrRemoveContacts(title: String, groups: [[CNContact]], removeIfEmpty: Bool = true) {
        if groups.isEmpty {
            if removeIfEmpty {
                buckets.removeAll { b in
                    if case .contact(let t, _) = b { return t == title }
                    return false
                }
            }
            return
        }
        for (i, g) in groups.enumerated() {
            let names = g.map { "\($0.givenName) \($0.familyName) (id:\($0.identifier))" }
            NSLog("[Scanner] contact group \(i): \(names)")
        }
        if let idx = buckets.firstIndex(where: { b in
            if case .contact(let t, _) = b { return t == title }
            return false
        }) {
            buckets[idx] = .contact(title: title, groups: groups)
        } else {
            buckets.append(.contact(title: title, groups: groups))
        }
    }

    @MainActor private func handleAppendOrRemoveCalendar(title: String, groups: [[EKEvent]], removeIfEmpty: Bool = true) {
        if groups.isEmpty {
            if removeIfEmpty {
                buckets.removeAll { b in
                    if case .calendar(let t, _) = b { return t == title }
                    return false
                }
            }
            return
        }
        if let idx = buckets.firstIndex(where: { b in
            if case .calendar(let t, _) = b { return t == title }
            return false
        }) {
            buckets[idx] = .calendar(title: title, groups: groups)
        } else {
            buckets.append(.calendar(title: title, groups: groups))
        }
    }

    // MARK: - Scanners
    private func scanMediaAssets(of mediaType: PHAssetMediaType) async throws -> [[String]] {
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in cont.resume(returning: ()) }
            }
            status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        }
        if status == .denied || status == .restricted { throw ScannerError.photoAccessDenied }

        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let assets = PHAsset.fetchAssets(with: mediaType, options: fetchOptions)

        await MainActor.run {
            if mediaType == .image { self.summary.photosCount = assets.count }
            else if mediaType == .video { self.summary.videosCount = assets.count }
        }

        var map = [String: [String]]()
        let assetManager = PHAssetResourceManager.default()
        let resourceOptions = PHAssetResourceRequestOptions()
        resourceOptions.isNetworkAccessAllowed = true

        var assetList: [PHAsset] = []
        assets.enumerateObjects { a, _, _ in assetList.append(a) }

        for asset in assetList {
            if Task.isCancelled { break }
            await updateStatus("Processing asset...")
            guard let resource = PHAssetResource.assetResources(for: asset).first else { continue }
            let hash = try await sha256ForAssetResource(resource: resource, assetManager: assetManager, options: resourceOptions)
            if Task.isCancelled { break }
            map[hash, default: []].append(asset.localIdentifier)
            await updateStatus("Scanned asset")
        }

        return map.values.filter { $0.count >= 2 }
    }

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

    private func scanContacts() async throws -> [[CNContact]] {
        let store = CNContactStore()
        try await requestContactsAccessIfNeeded(store: store)

        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey, CNContactEmailAddressesKey, CNContactIdentifierKey] as [CNKeyDescriptor]
        var contacts: [CNContact] = []
        let req = CNContactFetchRequest(keysToFetch: keys)
        try store.enumerateContacts(with: req) { contact, _ in
            contacts.append(contact)
        }

        await MainActor.run { self.summary.contactsCount = contacts.count }

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

        return groupsMap.values.filter { $0.count >= 2 }
    }

    private func requestContactsAccessIfNeeded(store: CNContactStore) async throws {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if status == .notDetermined {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                store.requestAccess(for: .contacts) { granted, error in
                    if let e = error { cont.resume(throwing: e); return }
                    if granted { cont.resume(returning: ()) }
                    else { cont.resume(throwing: ScannerError.contactsAccessDenied) }
                }
            }
        } else if status == .denied || status == .restricted {
            throw ScannerError.contactsAccessDenied
        }
    }

    private func normalizePhone(_ raw: String) -> String {
        let digits = raw.filter { $0.isNumber }
        return String(digits.suffix(11))
    }

    private func normalizeEmail(_ raw: String) -> String {
        return raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func scanCalendar() async throws -> [[EKEvent]] {
        let store = EKEventStore()
        try await requestCalendarAccessIfNeeded(store: store)

        let calendars = store.calendars(for: .event)
        let now = Date()
        let oneYear = Calendar.current.date(byAdding: .year, value: 1, to: now)!
        let predicate = store.predicateForEvents(withStart: now, end: oneYear, calendars: calendars)
        let events = store.events(matching: predicate)
        await MainActor.run { self.summary.calendarCount = events.count }

        var map = [String: [EKEvent]]()
        for e in events {
            guard let title = e.title, !title.isEmpty else { continue }
            let rounded = Int(e.startDate.timeIntervalSince1970 / 60)
            let key = "\(title) | \(rounded)"
            map[key, default: []].append(e)
        }
        return map.values.filter { $0.count >= 2 }
    }

    private func requestCalendarAccessIfNeeded(store: EKEventStore) async throws {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .notDetermined {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                store.requestAccess(to: .event) { granted, error in
                    if let e = error { cont.resume(throwing: e); return }
                    if granted { cont.resume(returning: ()) }
                    else { cont.resume(throwing: ScannerError.calendarAccessDenied) }
                }
            }
        } else if status == .denied || status == .restricted {
            throw ScannerError.calendarAccessDenied
        }
    }
}

// MARK: - MainCardsView
struct MainCardsView: View {
    @StateObject private var scanner = ScannerManager()
    @State private var showResultsSheet = false

    // show non-destructive backup notification toast
    @State private var lastBackupRecord: ActionRecord? = nil
    @State private var showBackupToast: Bool = false

    @State private var showErrorAlert: Bool = false
    @State private var alertMessage: String = ""

    @State private var lastTotalGroups: Int = 0
    @State private var showNoDuplicatesToast: Bool = false

    private let cardCorner: CGFloat = 16

    // recommended sizes — tweak these to taste
    private var maxAnimationSize: CGFloat { 160 }               // maximum width/height for Lottie radar
    private var overlayPadding: CGFloat { 16 }                  // padding inside the scanning overlay
    private var fabSize: CGFloat { 52 }                         // diameter of floating results button

    private var scanningAnimationSize: CGFloat {
        // use up to 45% of width but never exceed maxAnimationSize
        let width = UIScreen.main.bounds.width
        return min(width * 0.45, maxAnimationSize)
    }

    // Lottie + pulse controls (optional visual polish)
    @State private var lottieColor: Color = .cyan
    @State private var animationSpeed: CGFloat = 1.5
    @State private var playAnimation: Bool = false   // control playback
    @State private var pulse: Bool = false           // controls glow pulse

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 14) {
                    header
                    card(title: "Photos", subtitle: "\(scanner.summary.photosCount) items", iconName: "photo.on.rectangle", tint: .blue) {
                        scanner.startMediaSweep(of: .image)
                    }

                    card(title: "Videos", subtitle: "\(scanner.summary.videosCount) items", iconName: "film", tint: .pink) {
                        scanner.startMediaSweep(of: .video)
                    }

                    card(title: "Contacts", subtitle: "\(scanner.summary.contactsCount) contacts", iconName: "person.2.fill", tint: .teal) {
                        scanner.startContactsSweep()
                    }

                    card(title: "Calendar", subtitle: "\(scanner.summary.calendarCount) events", iconName: "calendar", tint: .green) {
                        scanner.startCalendarSweep()
                    }

                    Spacer(minLength: 48)
                }
                .padding(18)
            }
            .background(Color(UIColor.systemBackground))
            .edgesIgnoringSafeArea(.all)

            // Scanning overlay (Breach-like style)
            if scanner.isScanning {
                Color.black.opacity(0.6).edgesIgnoringSafeArea(.all)

                ZStack {
                    Circle()
                        .fill(lottieColor.opacity(0.22))
                        .frame(width: scanningAnimationSize * 1.6, height: scanningAnimationSize * 1.6)
                        .scaleEffect(pulse ? 1.2 : 0.8)
                        .opacity(pulse ? 0.0 : 1.0)
                        .animation(Animation.easeOut(duration: 1.2).repeatForever(autoreverses: false), value: pulse)

                    LottieView(name: "radar_scan", loopMode: .loop, speed: Double(animationSpeed), play: playAnimation)
                        .frame(width: scanningAnimationSize, height: scanningAnimationSize)
                        .background(lottieColor.opacity(0.12))
                        .clipShape(Circle())
                        .allowsHitTesting(false)

                    VStack(spacing: 8) {
                        Spacer(minLength: scanningAnimationSize/2 + 12)
                        VStack(spacing: 6) {
                            Text(scanner.statusText)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                            Text(scanner.progressText)
                                .font(.system(size: 13))
                                .foregroundColor(.gray)
                            Button(action: { scanner.stopScan() }) {
                                Text("Cancel Scan")
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Color.clear)
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.blue, lineWidth: 1))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 24)
                            .frame(maxWidth: 260)
                        }
                        Spacer(minLength: 8)
                    }
                }
                .padding(overlayPadding)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)
                .padding(24)
                .transition(.opacity)
                .onAppear {
                    lottieColor = .cyan
                    animationSpeed = 1.5
                    playAnimation = true
                    pulse = true
                }
                .onDisappear {
                    playAnimation = false
                    pulse = false
                }
            }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    if !scanner.buckets.isEmpty {
                        Button(action: { showResultsSheet = true }) {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 20, weight: .semibold))
                                .frame(width: fabSize, height: fabSize)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .clipShape(Circle())
                                .shadow(radius: 6)
                        }
                        .padding()
                    }
                }
            }

            // Backup toast (non-destructive): show summary only, auto-dismiss
            if let rec = lastBackupRecord, showBackupToast {
                VStack {
                    Spacer()
                    HStack {
                        Text(rec.summary).foregroundColor(.white)
                        Spacer()
                    }
                    .padding()
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(12)
                    .padding()
                }
                .transition(.move(edge: .bottom))
                .animation(.easeInOut, value: showBackupToast)
            }

            if showNoDuplicatesToast {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("No duplicates found")
                            .foregroundColor(.white)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 16)
                            .background(Color.black.opacity(0.8))
                            .cornerRadius(12)
                        Spacer()
                    }
                    .padding(.bottom, 48)
                }
                .transition(.move(edge: .bottom))
                .animation(.easeInOut, value: showNoDuplicatesToast)
            }
        }
        .sheet(isPresented: $showResultsSheet) {
            ResultsListView()
                .environmentObject(scanner)
        }
        .environmentObject(scanner)
        .alert(isPresented: $showErrorAlert) {
            Alert(title: Text("Error"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
        .onReceive(scanner.$buckets.receive(on: RunLoop.main)) { buckets in
            let totalGroups = buckets.reduce(into: 0) { acc, b in
                switch b {
                case .media(_, let groups): acc += groups.count
                case .contact(_, let groups): acc += groups.count
                case .calendar(_, let groups): acc += groups.count
                }
            }
            if totalGroups > 0 && totalGroups > lastTotalGroups && !showResultsSheet {
                showResultsSheet = true
            }
            lastTotalGroups = totalGroups
        }
        .onReceive(scanner.$scanFinishedWithNoDuplicates.receive(on: RunLoop.main)) { empty in
            guard empty else { return }
            showNoDuplicatesToast = true
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run { showNoDuplicatesToast = false }
                await MainActor.run { scanner.scanFinishedWithNoDuplicates = false }
            }
        }
        // Listen for safe backup records (non-destructive)
        .onReceive(NotificationCenter.default.publisher(for: .didCreateBackupRecord)) { note in
            guard let rec = note.object as? ActionRecord else { return }
            Task { @MainActor in
                self.lastBackupRecord = rec
                self.showBackupToast = true
                // auto-dismiss after 2 seconds
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run {
                    self.showBackupToast = false
                    self.lastBackupRecord = nil
                }
            }
        }
    }

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

    // Larger card implementation for bigger optimization boxes
    private func card(title: String, subtitle: String, iconName: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: iconName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 56, height: 56)
                    .foregroundColor(tint)
                    .padding(.trailing, 8)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.system(size: 18, weight: .semibold)).foregroundColor(.white)
                    Text(subtitle).font(.system(size: 14)).foregroundColor(.gray)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 16)
            .frame(minHeight: 110)
            .background(Color(UIColor.systemGray6))
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(UIColor.systemGray4), lineWidth: 1))
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - ResultsListView and details (Locate-only; no delete/merge)
struct ResultsListView: View {
    @EnvironmentObject var scanner: ScannerManager
    @Environment(\.presentationMode) var presentation

    var body: some View {
        NavigationView {
            List {
                ForEach(Array(scanner.buckets.enumerated()), id: \.offset) { idx, bucket in
                    Section(header: Text(bucketTitle(bucket))) {
                        switch bucket {
                        case .media(_, let groups):
                            ForEach(Array(groups.enumerated()), id: \.offset) { gidx, group in
                                NavigationLink(destination: MediaGroupDetailView(localIdentifiers: group)) {
                                    Text("Group \(gidx + 1) (\(group.count) items)")
                                }
                                // NO swipe actions — tapping navigates to occurrence
                            }
                        case .contact(_, let groups):
                            ForEach(Array(groups.enumerated()), id: \.offset) { gidx, group in
                                NavigationLink(destination: ContactGroupDetailView(group: group).environmentObject(scanner)) {
                                    Text("Group \(gidx + 1) (\(group.count) contacts)")
                                }
                                // Contacts detail handles safe view/merge flows
                            }
                        case .calendar(_, let groups):
                            ForEach(Array(groups.enumerated()), id: \.offset) { gidx, group in
                                NavigationLink(destination: CalendarGroupDetailView(group: group).environmentObject(scanner)) {
                                    Text("Group \(gidx + 1) (\(group.count) events)")
                                }
                                // NO swipe actions — tapping navigates to occurrence (Calendar)
                            }
                        }
                    }
                }
            }
            .listStyle(GroupedListStyle())
            .navigationBarTitle("Scan Results", displayMode: .inline)
            .navigationBarItems(trailing: Button("Done") { presentation.wrappedValue.dismiss() })
        }
    }

    private func bucketTitle(_ b: DuplicateBucket) -> String {
        switch b {
        case .media(let title, _): return title
        case .contact(let title, _): return title
        case .calendar(let title, _): return title
        }
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
                        // Open Photos app so the user can inspect the asset in their Photos library
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

// MARK: - Contact detail view wrapper (fetches required keys)
struct ContactDetailView: UIViewControllerRepresentable {
    let contact: CNContact

    func makeUIViewController(context: Context) -> UIViewController {
        let store = CNContactStore()
        // fetch the required keys for CNContactViewController safely
        let requiredKeys: [CNKeyDescriptor] = [CNContactViewController.descriptorForRequiredKeys()] as [CNKeyDescriptor]

        do {
            let unified = try store.unifiedContact(withIdentifier: contact.identifier, keysToFetch: requiredKeys)
            let contactVC = CNContactViewController(for: unified)
            contactVC.allowsEditing = false
            contactVC.allowsActions = true
            contactVC.view.backgroundColor = .systemBackground
            let nav = UINavigationController(rootViewController: contactVC)
            return nav
        } catch {
            return UIHostingController(rootView: Text("Unable to load contact details").padding())
        }
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

// Contact group detail only shows contacts and allows tapping to view in the safe contact view controller.
struct ContactGroupDetailView: View {
    @EnvironmentObject var scanner: ScannerManager
    @Environment(\.presentationMode) var presentation
    let group: [CNContact]

    var body: some View {
        List {
            ForEach(group, id: \.identifier) { c in
                NavigationLink(destination: ContactDetailView(contact: c)) {
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
        }
        .navigationTitle("Duplicates")
    }
}

// Calendar group detail: show events; tapping opens Calendar (calshow:)
// NOTE: No Delete button here — user is taken to Calendar to act on the event.
struct CalendarGroupDetailView: View {
    @EnvironmentObject var scanner: ScannerManager
    @Environment(\.presentationMode) var presentation
    let group: [EKEvent]

    var body: some View {
        List {
            ForEach(group, id: \.eventIdentifier) { e in
                Button(action: { openInCalendar(event: e) }) {
                    VStack(alignment: .leading) {
                        Text(e.title ?? "Untitled").font(.headline)
                        Text(e.startDate, style: .date).font(.subheadline)
                        Text("Tap to open in Calendar").font(.caption).foregroundColor(.gray)
                    }
                }
            }
        }
        .navigationTitle("Duplicate Events")
        // intentionally no destructive actions here — the user is taken to Calendar to inspect/manage
    }

    private func openInCalendar(event: EKEvent) {
        // calshow expects seconds since reference date as a fractional URL: calshow:<timestamp>
        let seconds = event.startDate.timeIntervalSinceReferenceDate
        if let url = URL(string: "calshow:\(seconds)") {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }
}
