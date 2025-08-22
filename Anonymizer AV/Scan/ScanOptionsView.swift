import SwiftUI

struct ScanOptionsView: View {
    @StateObject private var scanSession = ScanSession() // root session
    @State private var showPicker = false

    var body: some View {
        NavigationStack {
            VStack {
                Spacer()

                VStack(spacing: 20) {
                    Text("Choose Files to Scan")
                        .font(.title3)
                        .fontWeight(.semibold)

                    // File picker button
                    Button(action: { showPicker = true }) {
                        HStack {
                            Image(systemName: "doc.on.doc.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.accentColor)
                            Text("Select Files")
                            Spacer()
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                    }
                    .buttonStyle(.plain)
                    .sheet(isPresented: $showPicker) {
                        DocumentPicker { urls in
                            // set selection only — do not auto-start scanning yet
                            scanSession.selectedFiles = urls
                        }
                    }

                    // Start Scan button (only visible when files selected)
                    if !scanSession.selectedFiles.isEmpty {
                        Button("Start Scan") {
                            // Start scanning using the selected files.
                            // This sets scanSession.showProgress = true inside startScan.
                            scanSession.startScan(with: scanSession.selectedFiles)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor))
                        .foregroundColor(.white)
                    }
                }
                .frame(maxWidth: 500)

                Spacer()
            }
            .padding()
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Scan")

            // IMPORTANT: place both navigationDestination modifiers on the same NavigationStack.
            // When showProgress flips true, ProgressView is pushed.
            // When finishScan() sets showResults = true, Results will be pushed on top.
            .navigationDestination(isPresented: $scanSession.showProgress) {
                ScanProgressView()
                    .environmentObject(scanSession)
            }
            .navigationDestination(isPresented: $scanSession.showResults) {
                ScanResultsView()
                    .environmentObject(scanSession)
            }
        }
        // provide session to any other views presented modally
        .environmentObject(scanSession)
    }
}
