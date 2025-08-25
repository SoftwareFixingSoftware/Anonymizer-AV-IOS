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

    private let manager = QuarantineManager.shared

    init(loadFromCoreData: Bool = true) {
        if loadFromCoreData {
            loadFilesFromCoreData()
        }
    }

    // MARK: - Persistence (Core Data)
    func loadFilesFromCoreData() {
        let entities = manager.listQuarantined()
        // Map Core Data entities to DTOs for UI
        files = entities.map { QuarantinedFile(entity: $0) }
    }

    // MARK: - CRUD operations wired to logic layer (QuarantineManager)
    func deleteFile(_ f: QuarantinedFile) {
        let success = manager.deleteFile(id: f.id)
        if success {
            // Remove from UI list
            files.removeAll { $0.id == f.id }
        } else {
            // Optionally: handle failure / show an alert
            print("QuarantineViewModel: failed to delete file with id \(f.id)")
        }
    }

    func restoreFile(_ f: QuarantinedFile) {
        let success = manager.restoreFile(id: f.id)
        if success {
            files.removeAll { $0.id == f.id }
        } else {
            print("QuarantineViewModel: failed to restore file with id \(f.id)")
        }
    }

    // MARK: - Filtering & Sorting
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
