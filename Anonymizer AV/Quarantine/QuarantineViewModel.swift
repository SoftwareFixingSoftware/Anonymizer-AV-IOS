// QuarantineViewModel.swift
import Foundation

@MainActor
final class QuarantineViewModel: ObservableObject {
    enum SortOption: String, CaseIterable, Identifiable {
        case dateNewest = "Date (Newest)"
        case dateOldest = "Date (Oldest)"
        case nameAZ = "Name (A–Z)"
        case nameZA = "Name (Z–A)"

        var id: String { rawValue }
    }

    @Published private(set) var files: [QuarantinedFile] = []
    @Published var searchText: String = ""
    @Published var sortOption: SortOption = .dateNewest

    // Expose errors for UI to present
    @Published var lastError: String?

    private let manager = QuarantineManager.shared
    private let dao = QuarantineDao()

    init(loadFromCoreData: Bool = true) {
        if loadFromCoreData {
            loadFilesFromCoreData()
        }
    }

    func loadFilesFromCoreData() {
        let entities = dao.getAll()
        files = entities.map { QuarantinedFile(entity: $0) }
    }

    @discardableResult
    func deleteFile(_ f: QuarantinedFile) -> Bool {
        let success = manager.deleteFile(id: f.id)
        if success {
            files.removeAll { $0.id == f.id }
            return true
        } else {
            // Provide a helpful diagnostic message
            let qDir = manager.quarantineDirectory()
            let storedName = URL(fileURLWithPath: f.filePath).lastPathComponent
            if let contents = try? FileManager.default.contentsOfDirectory(at: qDir, includingPropertiesForKeys: nil, options: []) {
                if let found = contents.first(where: { $0.lastPathComponent.lowercased().contains(storedName.lowercased()) }) {
                    lastError = "Failed to delete quarantined file. Found a candidate at \(found.path) but deletion failed (check file locks/permissions)."
                } else {
                    lastError = "Failed to delete quarantined file. File not found inside current quarantine directory."
                }
            } else {
                lastError = "Failed to delete quarantined file and could not inspect quarantine folder."
            }
            return false
        }
    }

    @discardableResult
    func restoreFile(_ f: QuarantinedFile) -> Bool {
        let success = manager.restoreFile(id: f.id)
        if success {
            files.removeAll { $0.id == f.id }
            return true
        } else {
            lastError = "Failed to restore \"\(f.fileName)\". On this platform use Export instead."
            return false
        }
    }

    // Filtering & sorting unchanged
    var filteredAndSortedFiles: [QuarantinedFile] {
        let filtered: [QuarantinedFile]
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            filtered = files
        } else {
            let q = searchText.lowercased()
            filtered = files.filter {
                $0.fileName.lowercased().contains(q) ||
                $0.classification.lowercased().contains(q) ||
                ($0.reason ?? "").lowercased().contains(q)
            }
        }

        switch sortOption {
        case .dateNewest:
            return filtered.sorted { $0.dateQuarantined > $1.dateQuarantined }
        case .dateOldest:
            return filtered.sorted { $0.dateQuarantined < $1.dateQuarantined }
        case .nameAZ:
            return filtered.sorted { $0.fileName.lowercased() < $1.fileName.lowercased() }
        case .nameZA:
            return filtered.sorted { $0.fileName.lowercased() > $1.fileName.lowercased() }
        }
    }
}
