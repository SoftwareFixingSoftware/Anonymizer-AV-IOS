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
                                            Button("Delete") { delete(url: item.fileURL) }
                                            Button("Quarantine") {
                                                quarantine(
                                                    url: item.fileURL,
                                                    classification: item.category,
                                                    reason: item.threatName
                                                )
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
                // 1) Tell navigation to hide results so the NavigationStack can pop this view.
                scanSession.showResults = false

                // 2) After the Results view is popped (next run loop), fully reset session so user can pick new files.
                DispatchQueue.main.async {
                    scanSession.reset()
                }

                // 3) Defensive dismiss in case this view was presented modally anywhere.
                //    If not needed in your setup it's harmless.
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
            let success = securityManager.deleteFile(url)
            DispatchQueue.main.async {
                if success { remove(url: url) }
            }
        }
    }

    private func quarantine(url: URL, classification: String, reason: String) {
        DispatchQueue.global().async {
            let success = securityManager.moveToQuarantine(url, classification: classification, reason: reason)
            DispatchQueue.main.async {
                if success { remove(url: url) }
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
}
