// QuarantineManager.swift
// Robust QuarantineManager with tolerant delete logic and safe quarantine copying.
//
// Depends on: QuarantineDao, QuarantineEntity, QuarantineDatabase (your existing Core Data stack)

import Foundation

final class QuarantineManager {
    static let shared = QuarantineManager()
    private let dao = QuarantineDao()
    private let fileManager = FileManager.default

    private init() {
        // Ensure quarantine dir exists early
        _ = quarantineDirectory()
    }

    // MARK: - Directory Helpers

    /// Application Support / Quarantine directory for this app container (public so other modules can reconstruct)
    func quarantineDirectory() -> URL {
        let dir = fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Quarantine", isDirectory: true)

        if !fileManager.fileExists(atPath: dir.path) {
            do {
                try fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("QuarantineManager: failed to create dir: \(error)")
            }
        }
        return dir
    }

    private func uniqueQuarantineURL(for src: URL) -> URL {
        let destName = "\(UUID().uuidString)__\(src.lastPathComponent)"
        return quarantineDirectory().appendingPathComponent(destName)
    }

    // MARK: - Normalization helpers

    /// Normalizes a possibly odd incoming URL representation into a usable file:// URL if possible.
    private func normalizeToFileURL(_ rawURL: URL) -> URL? {
        if rawURL.isFileURL { return URL(fileURLWithPath: rawURL.path) }

        var candidate = rawURL.absoluteString

        if let range = candidate.range(of: "NSURL=") {
            candidate = String(candidate[range.upperBound...])
            candidate = candidate.trimmingCharacters(in: CharacterSet(charactersIn: "}\n\r\t"))
        }

        if candidate.hasPrefix("file://"), let u = URL(string: candidate), u.isFileURL {
            return URL(fileURLWithPath: u.path)
        }

        let decoded = candidate.removingPercentEncoding ?? candidate
        if decoded.hasPrefix("/") {
            return URL(fileURLWithPath: decoded)
        }

        let fallbackPath = rawURL.path
        if !fallbackPath.isEmpty {
            return URL(fileURLWithPath: fallbackPath)
        }

        return nil
    }

    // MARK: - Quarantine (copy into app container)

    /// Copies the provided URL into the app Quarantine folder. Returns true on success.
    func quarantineFile(url rawURL: URL, classification: String, reason: String) -> Bool {
        guard let srcURL = normalizeToFileURL(rawURL) else {
            print("QuarantineManager: cannot normalize incoming URL: '\(rawURL.absoluteString)'")
            return false
        }

        print("QuarantineManager: normalized srcURL='\(srcURL.absoluteString)' isFileURL=\(srcURL.isFileURL) path='\(srcURL.path)'")

        guard fileManager.fileExists(atPath: srcURL.path) else {
            print("QuarantineManager: source file does NOT exist at path: \(srcURL.path)")
            return false
        }

        // quick read test
        do {
            let fh = try FileHandle(forReadingFrom: srcURL)
            try fh.close()
        } catch {
            print("QuarantineManager: failed to open source file for reading. Error: \(error). Path: \(srcURL.path)")
            return false
        }

        let destURL = uniqueQuarantineURL(for: srcURL)

        var didStartAccess = false
        if srcURL.startAccessingSecurityScopedResource() { didStartAccess = true }
        defer { if didStartAccess { srcURL.stopAccessingSecurityScopedResource() } }

        // Ensure quarantine dir exists
        let qDir = quarantineDirectory()
        if !fileManager.fileExists(atPath: qDir.path) {
            do { try fileManager.createDirectory(at: qDir, withIntermediateDirectories: true, attributes: nil) }
            catch {
                print("QuarantineManager: failed to create quarantine dir: \(error)")
                return false
            }
        }

        // Use NSFileCoordinator .forUploading to request a provider-prepared copy
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var primaryCopyError: Error?
        var coordinatedSuccess = false

        coordinator.coordinate(readingItemAt: srcURL, options: [.forUploading], error: &coordinationError) { coordinatedURL in
            do {
                try fileManager.copyItem(at: coordinatedURL, to: destURL)
                // Insert DB record (QuarantineDao will persist only lastPathComponent as filename)
                dao.insert(
                    fileName: srcURL.lastPathComponent,
                    classification: classification,
                    reason: reason,
                    filePath: destURL.path,
                    originalPath: srcURL.path
                )
                coordinatedSuccess = true
            } catch {
                primaryCopyError = error
            }
        }

        if coordinatedSuccess {
            print("QuarantineManager: coordinated copy succeeded -> \(destURL.path)")
            return true
        }

        if let coordErr = coordinationError {
            print("QuarantineManager: NSFileCoordinator coordination error: \(coordErr.domain) code:\(coordErr.code) userInfo:\(coordErr.userInfo)")
        }

        // fallback: streaming copy (avoid memory spikes)
        if primaryCopyError != nil {
            do {
                try streamCopy(from: srcURL, to: destURL)
                dao.insert(
                    fileName: srcURL.lastPathComponent,
                    classification: classification,
                    reason: reason,
                    filePath: destURL.path,
                    originalPath: srcURL.path
                )
                print("QuarantineManager: fallback stream copy succeeded -> \(destURL.path)")
                return true
            } catch {
                printDetailedCopyError(error: error, src: srcURL, dest: destURL, prior: (primaryCopyError as NSError?))
                return false
            }
        }

        print("QuarantineManager: unknown failure — no specific error from coordinator/copy")
        return false
    }

    // MARK: - Restore

    func restoreFile(id: UUID) -> Bool {
        guard let entity = dao.getById(id) else { return false }

        let quarantineURL = URL(fileURLWithPath: entity.filePath)
        let originalURL = URL(fileURLWithPath: entity.originalPath)

        #if os(iOS) || os(tvOS) || os(watchOS)
        print("QuarantineManager.restoreFile: restore not supported on this platform; use Export/Share instead.")
        return false
        #else
        do {
            let parent = originalURL.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: parent.path) {
                try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            }

            var dest = originalURL
            if fileManager.fileExists(atPath: dest.path) {
                dest = parent.appendingPathComponent("\(UUID().uuidString)__\(originalURL.lastPathComponent)")
            }

            try fileManager.moveItem(at: quarantineURL, to: dest)

            if let ent = dao.getById(id) { dao.delete(ent) }
            return true
        } catch {
            print("QuarantineManager.restoreFile failed: \(error)")
            return false
        }
        #endif
    }

    // MARK: - Delete (robust & tolerant)

    // Normalize filename for matching: percent-decode + trim + lowercase
    private func normalizedName(_ name: String) -> String {
        let decoded = name.removingPercentEncoding ?? name
        return decoded.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // Strip UUID prefix "UUID__filename" -> "filename"
    private func stripUuidPrefix(_ name: String) -> String {
        if let idx = name.range(of: "__") {
            return String(name[idx.upperBound...])
        }
        return name
    }

    // Build candidate variants of the stored name
    private func candidateVariants(for stored: String) -> [String] {
        let last = URL(fileURLWithPath: stored).lastPathComponent
        let trimmed = last.trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = stripUuidPrefix(trimmed)
        let decoded = (last.removingPercentEncoding ?? last)
        let decodedStripped = stripUuidPrefix(decoded)
        return Array(Set([last, trimmed, stripped, decoded, decodedStripped].map { normalizedName($0) }))
    }

    /// Delete quarantined file and DB entry if appropriate.
    /// Strategy:
    /// 1) If entity.filePath points inside this container's quarantine dir => delete file (if exists) and DB entry.
    /// 2) Otherwise search the current quarantine dir for candidate filenames (tolerant matching) and delete the first match found, then remove DB entry.
    /// 3) If no match found, refuse to delete (returns false) so caller can surface an error.
    func deleteFile(id: UUID) -> Bool {
        guard let entity = dao.getById(id) else {
            print("QuarantineManager.deleteFile: no entity for id \(id)")
            return false
        }

        let stored = entity.filePath // may be filename-only (preferred) or absolute (legacy)
        let qDir = quarantineDirectory()
        let standardizedQDir = qDir.standardizedFileURL.resolvingSymlinksInPath()

        // Determine stored URL candidate
        let storedURL: URL
        if stored.hasPrefix("/") {
            storedURL = URL(fileURLWithPath: stored).standardizedFileURL.resolvingSymlinksInPath()
        } else {
            storedURL = qDir.appendingPathComponent(stored).standardizedFileURL.resolvingSymlinksInPath()
        }

        // containment helper
        func isChild(_ child: URL, of parent: URL) -> Bool {
            let p = parent.standardizedFileURL.resolvingSymlinksInPath()
            let c = child.standardizedFileURL.resolvingSymlinksInPath()
            if p.path == c.path { return true }
            let pComp = p.pathComponents
            let cComp = c.pathComponents
            guard cComp.count > pComp.count else { return false }
            return Array(cComp.prefix(pComp.count)) == pComp
        }

        // Case A: storedURL is inside current quarantine dir -> delete or remove DB entry
        if isChild(storedURL, of: standardizedQDir) {
            do {
                if fileManager.fileExists(atPath: storedURL.path) {
                    try fileManager.removeItem(at: storedURL)
                    print("QuarantineManager.deleteFile: removed file at storedURL: \(storedURL.path)")
                } else {
                    print("QuarantineManager.deleteFile: stored file not found at storedURL (removing DB entry): \(storedURL.path)")
                }
                dao.delete(entity)
                return true
            } catch {
                print("QuarantineManager.deleteFile: failed to remove storedURL: \(error)")
                return false
            }
        }

        // Case B: fallback search in current quarantine dir using tolerant matching
        let variants = candidateVariants(for: stored)
        do {
            let contents = try fileManager.contentsOfDirectory(at: standardizedQDir, includingPropertiesForKeys: nil, options: [])
            // First try normalized exact match
            if let match = contents.first(where: { fileURL in
                return variants.contains(normalizedName(fileURL.lastPathComponent))
            }) {
                do {
                    try fileManager.removeItem(at: match)
                    print("QuarantineManager.deleteFile: found and removed matching file in current quarantine dir: \(match.path)")
                    dao.delete(entity)
                    return true
                } catch {
                    print("QuarantineManager.deleteFile: found match but failed to remove \(match.path): \(error)")
                    return false
                }
            }

            // Loose match: strip uuid prefix then compare
            if let loose = contents.first(where: { fileURL in
                let candidateStripped = normalizedName(stripUuidPrefix(fileURL.lastPathComponent))
                return variants.contains(candidateStripped) || variants.contains(normalizedName(fileURL.lastPathComponent))
            }) {
                do {
                    try fileManager.removeItem(at: loose)
                    print("QuarantineManager.deleteFile: found (loose) and removed matching file: \(loose.path)")
                    dao.delete(entity)
                    return true
                } catch {
                    print("QuarantineManager.deleteFile: loose match found but failed removal \(loose.path): \(error)")
                    return false
                }
            }

            // Not found
            print("QuarantineManager.deleteFile: refusing to delete because stored path points outside current quarantine dir and no matching file found.")
            print("  current qDir: \(standardizedQDir.path)")
            print("  stored value: \(stored)")
            return false
        } catch {
            print("QuarantineManager.deleteFile: failed listing quarantine dir: \(error)")
            return false
        }
    }

    // MARK: - Streaming copy fallback

    private func streamCopy(from src: URL, to dest: URL, bufferSize: Int = 64 * 1024) throws {
        guard let input = InputStream(url: src) else {
            throw NSError(domain: NSCocoaErrorDomain, code: 256, userInfo: [NSLocalizedDescriptionKey: "Failed to open input stream"])
        }
        guard let output = OutputStream(url: dest, append: false) else {
            throw NSError(domain: NSCocoaErrorDomain, code: 256, userInfo: [NSLocalizedDescriptionKey: "Failed to open output stream"])
        }

        input.open()
        output.open()
        defer {
            input.close()
            output.close()
        }

        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while input.hasBytesAvailable {
            let read = input.read(buffer, maxLength: bufferSize)
            if read < 0 {
                throw input.streamError ?? NSError(domain: NSCocoaErrorDomain, code: Int(read), userInfo: nil)
            } else if read == 0 {
                break
            }
            var written = 0
            while written < read {
                let w = output.write(buffer.advanced(by: written), maxLength: read - written)
                if w <= 0 {
                    throw output.streamError ?? NSError(domain: NSCocoaErrorDomain, code: Int(w), userInfo: nil)
                }
                written += w
            }
        }
    }

    // MARK: - Debugging helper

    private func printDetailedCopyError(error: Error, src: URL, dest: URL, prior: NSError?) {
        print("QuarantineManager: copy fallback failed.")
        print(" Source: \(src.path)")
        print(" Dest:   \(dest.path)")
        if let ns = error as NSError? {
            print(" Error: \(ns.domain) code:\(ns.code) userInfo:\(ns.userInfo)")
        } else {
            print(" Error: \(error.localizedDescription)")
        }
        if let p = prior {
            print(" Prior error: \(p.domain) code:\(p.code) userInfo:\(p.userInfo)")
        }
    }

    // MARK: - Queries passthrough

    func listQuarantined() -> [QuarantineEntity] {
        return dao.getAll()
    }

    func getFile(byId id: UUID) -> QuarantineEntity? {
        return dao.getById(id)
    }
}
