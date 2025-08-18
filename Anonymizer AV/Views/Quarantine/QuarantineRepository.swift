// QuarantineRepository.swift
import Foundation

final class QuarantineRepository {
    static let shared = QuarantineRepository()
    private init() {}

    private let filename = "quarantine.json"
    private var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(filename)
    }

    func load() -> [QuarantinedFile] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([QuarantinedFile].self, from: data)
        } catch {
            print("QuarantineRepository.load() failed:", error)
            return []
        }
    }

    func save(_ files: [QuarantinedFile]) {
        do {
            let data = try JSONEncoder().encode(files)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("QuarantineRepository.save() failed:", error)
        }
    }
}
