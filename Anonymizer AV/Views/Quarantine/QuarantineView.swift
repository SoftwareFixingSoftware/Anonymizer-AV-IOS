// QuarantineView.swift
import SwiftUI

struct QuarantineView: View {
    @StateObject private var vm = QuarantineViewModel()
    @State private var showDeleteConfirm: Bool = false
    @State private var showRestoreConfirm: Bool = false
    @State private var pendingFile: QuarantinedFile?

    var body: some View {
        NavigationStack {
            Group {
                if vm.filteredAndSortedFiles.isEmpty {
                    VStack(spacing: 16) {
                        Image("ic_quarantine_empty")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 96, height: 96)
                            .opacity(0.9)
                        Text("No quarantined files")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(vm.filteredAndSortedFiles) { file in
                            QuarantinedFileRow(
                                file: file,
                                onRestore: { requestRestore(file) },
                                onDelete: { requestDelete(file) }
                            )
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(PlainListStyle())
                    .refreshable {
                        vm.loadFilesFromRepo()
                    }
                }
            }
            .navigationTitle("Quarantine")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Picker("Sort", selection: $vm.sortOption) {
                            ForEach(QuarantineViewModel.SortOption.allCases, id: \.self) { opt in
                                Text(opt.rawValue).tag(opt)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { vm.loadFilesFromRepo() }) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .searchable(text: $vm.searchText, placement: .navigationBarDrawer(displayMode: .automatic))
            // Delete confirm
            .alert("Delete file", isPresented: $showDeleteConfirm, presenting: pendingFile) { file in
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    vm.deleteFile(file)
                }
            } message: { file in
                Text("Delete \(file.fileName)? This action cannot be undone.")
            }
            // Restore confirm
            .alert("Restore file", isPresented: $showRestoreConfirm, presenting: pendingFile) { file in
                Button("Cancel", role: .cancel) {}
                Button("Restore") {
                    vm.restoreFile(file)
                }
            } message: { file in
                Text("Restore \(file.fileName) to its original location?")
            }
        }
    }

    // MARK: - Actions
    private func requestDelete(_ f: QuarantinedFile) {
        pendingFile = f
        showDeleteConfirm = true
    }

    private func requestRestore(_ f: QuarantinedFile) {
        pendingFile = f
        showRestoreConfirm = true
    }
}
