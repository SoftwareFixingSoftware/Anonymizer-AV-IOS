import SwiftUI

struct ScanResultsView: View {
    @EnvironmentObject var scanSession: ScanSession
    @Environment(\.dismiss) private var dismiss
    @State private var categorized: [String: [ScanResultItemModel]] = [:]

    private let securityManager = SecurityManager.shared

    var body: some View {
        VStack {
            Text("🛡️ Threats Detected: \(scanSession.threats.count)")
                .font(.headline)
                .padding()

            if scanSession.threats.isEmpty {
                Text("No threats found")
                    .padding()
            } else {
                List {
                    ForEach(Array(categorized.keys), id: \.self) { key in
                        if let items = categorized[key] {
                            Section(header: Text("📁 \(key)")) {
                                ForEach(items) { item in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("⚠️ \(item.fileName)")
                                            .font(.subheadline)

                                        Text(item.fileURL.path)
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                            .lineLimit(1)
                                            .truncationMode(.middle)

                                        Text("🚨 \(item.threatName)")
                                            .font(.caption2)
                                            .foregroundColor(.red)

                                        HStack {
                                            // Only allow Delete on files inside our app container
                                            #if os(iOS)
                                            if isInsideAppContainer(item.fileURL) {
                                                Button("Delete") { delete(url: item.fileURL) }
                                            }
                                            #else
                                            Button("Delete") { delete(url: item.fileURL) }
                                            #endif

                                            Button("Quarantine") {
                                                quarantine(url: item.fileURL, classification: item.category, reason: item.threatName)
                                            }
                                        }
                                        .font(.caption)
                                    }
                                    .padding(.vertical, 6)
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }

            Button("Scan Again") {
                scanSession.showResults = false
                DispatchQueue.main.async {
                    scanSession.reset()
                }
                dismiss()
            }
            .padding()
        }
        .navigationTitle("Scan Results")
        .navigationBarBackButtonHidden(true)
        .onAppear {
            categorized = Self.categorize(scanSession.threats)
        }
    }

    // MARK: - File Actions

    private func delete(url: URL) {
        DispatchQueue.global().async {
            // allow deleting only if inside app container
            if isInsideAppContainer(url) {
                var deleted = false
                do {
                    try FileManager.default.removeItem(at: url)
                    deleted = true
                    print("Deleted sandbox file: \(url.path)")
                } catch {
                    print("Failed to delete sandbox file: \(error)")
                    deleted = false
                }

                DispatchQueue.main.async {
                    if deleted { remove(url: url) }
                }
            } else {
                DispatchQueue.main.async {
                    print("Delete attempted on external file — not permitted.")
                    // Optionally show an alert to the user
                }
            }
        }
    }

    private func quarantine(url: URL, classification: String, reason: String) {
        DispatchQueue.global().async {
            // Diagnostic: log raw URL and path
            print("ScanResultsView: quarantining rawURL='\(url.absoluteString)' path='\(url.path)' isFileURL=\(url.isFileURL)")

            let success = securityManager.moveToQuarantine(url, classification: classification, reason: reason)
            DispatchQueue.main.async {
                if success { remove(url: url) }
                else { print("Quarantine failed for \(url.path)") }
            }
        }
    }

    private func remove(url: URL) {
        var updated = categorized
        for (k, v) in categorized {
            if let idx = v.firstIndex(where: { $0.fileURL == url }) {
                var copy = v
                copy.remove(at: idx)
                updated[k] = copy
            }
        }
        categorized = updated
    }

    // MARK: - Helpers

    static private func categorize(_ threats: [String]) -> [String: [ScanResultItemModel]] {
        var map: [String: [ScanResultItemModel]] = [:]
        for t in threats {
            let parts = t.split(separator: "→", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            let uriStr = parts.first ?? ""
            let reason = parts.count > 1 ? String(parts[1]) : "Unknown threat"
            let url = URL(string: uriStr) ?? URL(fileURLWithPath: uriStr)
            let category = getCategoryFromPath(url.path)
            map[category, default: []].append(
                ScanResultItemModel(
                    fileName: fileName(from: url),
                    infected: true,
                    fileURL: url,
                    category: category,
                    threatName: reason
                )
            )
        }
        return map
    }

    static private func getCategoryFromPath(_ path: String) -> String {
        let lower = path.lowercased()
        if lower.hasSuffix(".apk") { return "APK Files" }
        if lower.range(of: "\\.(docx?|pdf|txt)$", options: .regularExpression) != nil { return "Documents" }
        if lower.range(of: "\\.(jpg|jpeg|png|mp4|mkv)$", options: .regularExpression) != nil { return "Media Files" }
        if lower.range(of: "\\.(zip|rar|7z)$", options: .regularExpression) != nil { return "Archives" }
        return "Others"
    }

    private func isInsideAppContainer(_ url: URL) -> Bool {
        let appDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return url.path.hasPrefix(appDir.path)
    }
}
