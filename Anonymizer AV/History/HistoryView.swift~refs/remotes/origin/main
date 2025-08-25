//
//  HistoryView.swift
//  Anonymizer AV
//
//  Created by gitiriku lucas mwangi on 20/08/2025.
//
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Model
struct ScanHistoryItem: Identifiable {
    let id = UUID()
    let scanType: String
    let rawDate: String
    let formattedDate: String
    let filesCount: Int
    let threatsCount: Int
    let duration: String
    let parsedDate: Date?
}

// MARK: - Main History View
struct HistoryView: View {
    @State private var historyItems: [ScanHistoryItem] = []
    @State private var currentSortOption: SortOption = .dateDesc
    @State private var isShowingDetails: Bool = false
    @State private var selectedItem: ScanHistoryItem?

    enum SortOption: String, CaseIterable, Identifiable {
        case dateDesc = "Date ↓"
        case dateAsc = "Date ↑"
        case threatsDesc = "Threats ↓"
        case threatsAsc = "Threats ↑"

        var id: String { rawValue }
    }

    var body: some View {
        NavigationView {
            Group {
                if historyItems.isEmpty {
                    Text("No scan history available")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(historyItems) { item in
                            HistoryCard(item: item) {
                                selectedItem = item
                                isShowingDetails = true
                            }
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(PlainListStyle())
                    .refreshable {
                        refreshHistory()
                    }
                }
            }
            .navigationTitle("Scan History")
            .toolbar {
                Menu {
                    Picker("Sort by", selection: $currentSortOption) {
                        ForEach(SortOption.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }
            .onChange(of: currentSortOption) { _ in
                sortHistory()
            }
            .onAppear {
                refreshHistory()
            }
            .alert("Scan Results", isPresented: $isShowingDetails, presenting: selectedItem) { item in
                Button("OK", role: .cancel) {}
                Button("Share") {
                    shareScanResults(item)
                }
            } message: { item in
                Text("""
                Date: \(item.formattedDate)

                Files scanned: \(item.filesCount)
                Threats found: \(item.threatsCount)
                """)
            }
        }
    }

    // MARK: - Data Logic
    private func refreshHistory() {
        // Placeholder — normally you’d fetch from ScanLogManager or persistence
        let demo = [
            ScanHistoryItem(
                scanType: "Scan",
                rawDate: "2025-08-20 10:00:00",
                formattedDate: "Aug 20, 2025 at 10:00 AM",
                filesCount: 120,
                threatsCount: 3,
                duration: "N/A",
                parsedDate: Date()
            ),
            ScanHistoryItem(
                scanType: "Scan",
                rawDate: "2025-08-19 14:00:00",
                formattedDate: "Aug 19, 2025 at 2:00 PM",
                filesCount: 200,
                threatsCount: 0,
                duration: "N/A",
                parsedDate: Date().addingTimeInterval(-86400)
            )
        ]
        historyItems = demo
        sortHistory()
    }

    private func sortHistory() {
        switch currentSortOption {
        case .dateDesc:
            historyItems.sort { ($0.parsedDate ?? Date.distantPast) > ($1.parsedDate ?? Date.distantPast) }
        case .dateAsc:
            historyItems.sort { ($0.parsedDate ?? Date.distantPast) < ($1.parsedDate ?? Date.distantPast) }
        case .threatsDesc:
            historyItems.sort { $0.threatsCount > $1.threatsCount }
        case .threatsAsc:
            historyItems.sort { $0.threatsCount < $1.threatsCount }
        }
    }

    private func shareScanResults(_ item: ScanHistoryItem) {
        let shareText = """
        Scan results:
        Date: \(item.formattedDate)
        Files scanned: \(item.filesCount)
        Threats found: \(item.threatsCount)
        """
        let av = UIActivityViewController(activityItems: [shareText], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(av, animated: true, completion: nil)
        }
    }
}

// MARK: - History Card (item_scan_history.xml equivalent)
struct HistoryCard: View {
    let item: ScanHistoryItem
    let onDetails: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(item.scanType)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()
                if item.threatsCount > 0 {
                    Text("\(item.threatsCount) threat\(item.threatsCount > 1 ? "s" : "")")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.2))
                        .foregroundColor(.red)
                        .clipShape(Capsule())
                }
            }

            Text(item.formattedDate)
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack {
                Label("\(item.filesCount) file\(item.filesCount != 1 ? "s" : "")",
                      systemImage: "doc")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Details", action: onDetails)
                    .font(.footnote)
                    .foregroundColor(.blue)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)))
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

// MARK: - Preview
struct HistoryView_Previews: PreviewProvider {
    static var previews: some View {
        HistoryView()
    }
}


