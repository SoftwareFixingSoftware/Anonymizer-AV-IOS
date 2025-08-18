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

    private let repo = QuarantineRepository.shared

    init(loadFromRepo: Bool = false) {
        if loadFromRepo {
            loadFilesFromRepo()
        } else {
            loadDummyFiles()
        }
    }

    // MARK: - Persistence
    func loadFilesFromRepo() {
        files = repo.load()
    }

    func saveToRepo() {
        repo.save(files)
    }

    // MARK: - CRUD operations
    func addFile(_ f: QuarantinedFile) {
        files.append(f)
        saveToRepo()
    }

    func deleteFile(_ f: QuarantinedFile) {
        guard let idx = files.firstIndex(of: f) else { return }
        files[idx].status = .deleted
        // Optionally remove from list completely:
        files.remove(at: idx)
        saveToRepo()
    }

    func restoreFile(_ f: QuarantinedFile) {
        guard let idx = files.firstIndex(of: f) else { return }
        files[idx].status = .restored
        // remove from quarantine view:
        files.remove(at: idx)
        saveToRepo()
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
                $0.threatName.lowercased().contains(q) ||
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

    // MARK: - Dummy Data (for now)
    func loadDummyFiles() {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"
        files = [
            QuarantinedFile(
                fileName: "malicious_app.apk",
                filePath: "/Downloads/malicious_app.apk",
                dateQuarantined: df.date(from: "2025-08-20 11:30") ?? Date(),
                threatName: "Trojan.Android.Generic",
                reason: "Detected via MD5 signature"
            ),
            QuarantinedFile(
                fileName: "cracked_game.exe",
                filePath: "/Documents/cracked_game.exe",
                dateQuarantined: df.date(from: "2025-08-18 09:15") ?? Date().addingTimeInterval(-2*86400),
                threatName: "Worm.Win32.Agent",
                reason: "Heuristic match"
            ),
            QuarantinedFile(
                fileName: "phishing_doc.pdf",
                filePath: "/Documents/phishing_doc.pdf",
                dateQuarantined: df.date(from: "2025-08-12 14:00") ?? Date().addingTimeInterval(-8*86400),
                threatName: "Heur.PDF.Phishing",
                reason: "Suspicious URLs"
            )
        ]
    }
}
