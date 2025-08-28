// QuarantineView.swift
// Quarantine list UI with export / preview / delete.
// Uses runtime fallback for missing `ic_quarantine_empty` asset (SF Symbol fallback).

import SwiftUI
import QuickLook

// Small wrapper so .sheet(item:) works with a URL
private struct ExportItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL

    static func == (lhs: ExportItem, rhs: ExportItem) -> Bool {
        return lhs.id == rhs.id
    }
}

struct QuarantineView: View {
    @StateObject private var vm = QuarantineViewModel()
    @State private var showDeleteConfirm: Bool = false
    @State private var showRestoreConfirm: Bool = false
    @State private var pendingFile: QuarantinedFile?

    // Export using sheet(item:)
    @State private var exportItem: ExportItem?

    // QuickLook preview
    @State private var showPreview: Bool = false
    @State private var previewURL: URL?

    // If user requested delete while preview/share was open, queue it here
    @State private var pendingDeleteAfterDismiss: QuarantinedFile?

    var body: some View {
        NavigationStack {
            Group {
                if vm.filteredAndSortedFiles.isEmpty {
                    VStack(spacing: 16) {
                        // Runtime fallback: prefer asset "ic_quarantine_empty", fall back to SF Symbol
                        #if canImport(UIKit)
                        if let ui = UIImage(named: "ic_quarantine_empty") {
                            Image(uiImage: ui)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 96, height: 96)
                                .opacity(0.9)
                                .accessibilityHidden(true)
                        } else {
                            Image(systemName: "archivebox.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 72, height: 72)
                                .opacity(0.85)
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                        #else
                        Image(systemName: "archivebox.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 72, height: 72)
                            .opacity(0.85)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        #endif

                        Text("No quarantined files")
                            .foregroundColor(.secondary)
                            .accessibilityLabel("No quarantined files")
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(vm.filteredAndSortedFiles) { file in
                            QuarantinedFileRow(
                                file: file,
                                onOpen: { openFile(file) },
                                onRestoreOrExport: { requestRestoreOrExport(file) },
                                onDelete: { requestDelete(file) }
                            )
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(PlainListStyle())
                    .refreshable {
                        vm.loadFilesFromCoreData()
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
                    Button(action: { vm.loadFilesFromCoreData() }) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .searchable(text: $vm.searchText, placement: .navigationBarDrawer(displayMode: .automatic))

            // Delete confirm
            .alert("Delete file", isPresented: $showDeleteConfirm, presenting: pendingFile) { file in
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    handleConfirmedDelete(file)
                }
            } message: { file in
                Text("Delete \(file.fileName)? This action cannot be undone.")
            }

            // Restore confirm (non-iOS)
            .alert("Restore file", isPresented: $showRestoreConfirm, presenting: pendingFile) { file in
                Button("Cancel", role: .cancel) {}
                Button("Restore") {
                    let success = vm.restoreFile(file)
                    if !success {
                        // vm.lastError will be shown by global error alert
                    }
                }
            } message: { file in
                Text("Restore \(file.fileName) to its original location?")
            }

            // Export sheet using item binding
            .sheet(item: $exportItem) { item in
                ActivityView(activityItems: [item.url])
                    .ignoresSafeArea()
            }

            // QuickLook sheet
            .sheet(isPresented: $showPreview) {
                if let url = previewURL {
                    QuickLookPreview(url: url)
                        .ignoresSafeArea()
                } else {
                    Text("No preview available")
                }
            }

            // Observe preview dismissal to run queued delete if any
            .onChange(of: showPreview) { newVal in
                if newVal == false, let pending = pendingDeleteAfterDismiss {
                    let success = vm.deleteFile(pending)
                    if !success {
                        // vm.lastError will present to user
                    }
                    pendingDeleteAfterDismiss = nil
                }
            }

            // Observe exportItem dismissal (when set to nil) similarly
            .onChange(of: exportItem) { newVal in
                if newVal == nil, let pending = pendingDeleteAfterDismiss {
                    let success = vm.deleteFile(pending)
                    if !success {
                        // vm.lastError will present to user
                    }
                    pendingDeleteAfterDismiss = nil
                }
            }

            // Global error alert (delete/restore/export failures surfaced by VM)
            .alert("Operation failed", isPresented: Binding(get: {
                vm.lastError != nil
            }, set: { newVal in
                if !newVal { vm.lastError = nil }
            })) {
                Button("OK", role: .cancel) { vm.lastError = nil }
            } message: {
                Text(vm.lastError ?? "Unknown error")
            }
        }
    }

    // MARK: - Actions

    private func requestDelete(_ f: QuarantinedFile) {
        pendingFile = f
        showDeleteConfirm = true
    }

    private func handleConfirmedDelete(_ f: QuarantinedFile) {
        // If preview is showing the same file, dismiss preview and queue deletion after dismissal
        if showPreview, let purl = previewURL, purl.path == f.filePath {
            pendingDeleteAfterDismiss = f
            showPreview = false
            return
        }

        // If share sheet is open for same file, clear it and queue deletion
        if let ex = exportItem, ex.url.path == f.filePath {
            pendingDeleteAfterDismiss = f
            exportItem = nil // dismiss share sheet
            return
        }

        // Otherwise delete immediately
        let success = vm.deleteFile(f)
        if !success {
            // vm.lastError will be displayed by global alert
        }
    }

    private func requestRestoreOrExport(_ f: QuarantinedFile) {
        #if os(iOS)
        let url = URL(fileURLWithPath: f.filePath)
        if FileManager.default.fileExists(atPath: url.path) {
            // If preview is open for same file, dismiss preview first to avoid conflicts
            if showPreview, previewURL?.path == f.filePath {
                // close preview then present export sheet after a small async hop
                previewURL = nil
                showPreview = false
                DispatchQueue.main.async {
                    exportItem = ExportItem(url: url)
                }
            } else {
                exportItem = ExportItem(url: url)
            }
        } else {
            vm.lastError = "Quarantined file not found: \(f.fileName)"
        }
        #else
        pendingFile = f
        showRestoreConfirm = true
        #endif
    }

    private func openFile(_ f: QuarantinedFile) {
        let url = URL(fileURLWithPath: f.filePath)
        if FileManager.default.fileExists(atPath: url.path) {
            previewURL = url
            showPreview = true
        } else {
            vm.lastError = "Quarantined file not found at path: \(f.filePath)"
        }
    }
}
