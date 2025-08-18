//
//  ScanOptionsView.swift
//  Anonymizer AV
//

import SwiftUI

struct ScanOptionsView: View {
    @State private var selectedFiles: [URL] = []
    @State private var showPicker = false
    
    var body: some View {
        NavigationStack {
            VStack {
                Spacer()
                
                // Centered content in a card
                QuarantineCard {
                    VStack(spacing: 20) {
                        
                        // Title
                        Text("Choose Scan Option")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, alignment: .center)
                        
                        // Select files card
                        Button(action: { showPicker = true }) {
                            HStack {
                                Image(systemName: "doc.on.doc.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.accentCyan)
                                Text("Select Files to Scan")
                                    .font(.body)
                                Spacer()
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.secondarySystemBackground))
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .sheet(isPresented: $showPicker) {
                            DocumentPicker { urls in
                                selectedFiles = urls
                            }
                        }
                        
                        // Selected file count
                        if !selectedFiles.isEmpty {
                            Text("\(selectedFiles.count) file(s) selected")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                        
                        // Start Scan button
                        Button(action: {
                            // TODO: Hook up to your scan logic
                        }) {
                            Label("Start Scan", systemImage: "waveform.path.ecg")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentCyan))
                                .foregroundColor(.white)
                        }
                        .disabled(selectedFiles.isEmpty)
                        
                        // Full Scan button
                        Button(action: {
                            // TODO: Hook up to your full scan logic
                        }) {
                            Label("Full Device Scan", systemImage: "desktopcomputer.trianglebadge.exclamationmark")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange))
                                .foregroundColor(.white)
                        }
                    }
                }
                .frame(maxWidth: 500) // keeps it compact in larger screens
                
                Spacer()
            }
            .padding()
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Scan")
        }
    }
}

// MARK: - Preview
struct ScanOptionsView_Previews: PreviewProvider {
    static var previews: some View {
        ScanOptionsView()
    }
}
