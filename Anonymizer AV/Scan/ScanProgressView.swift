import SwiftUI

struct ScanProgressView: View {
    @EnvironmentObject var scanSession: ScanSession
    @Environment(\.dismiss) private var dismiss

    // local UI animation state only
    @State private var rotation: Double = 0
    @State private var bugColor: Color = .red
    let bugColors: [Color] = [.red, .green, .yellow, .cyan, .purple, .red]

    var body: some View {
        VStack(spacing: 16) {
            // Animated Bug Icon
            Image(systemName: "ant.fill")
                .resizable()
                .frame(width: 64, height: 64)
                .rotationEffect(.degrees(rotation))
                .foregroundColor(bugColor)
                .onAppear { startBugAnimation() }

            // ProgressBar - use fractional progress from session (0.0...1.0)
            ProgressView(value: clampedProgressFraction)
                .progressViewStyle(LinearProgressViewStyle(tint: .green))
                .frame(maxWidth: .infinity)
                .scaleEffect(x: 1, y: 2, anchor: .center)
                .padding(.horizontal)

            // Current File Text (from session)
            Text("Scanning: \(scanSession.currentFile.isEmpty ? "…" : scanSession.currentFile)")
                .font(.subheadline)

            // Files scanned text (counts)
            Text("Files scanned: \(scanSession.progressCount)/\(scanSession.selectedFiles.count)")
                .font(.caption)
                .foregroundColor(.gray)

            // Console output — use session.consoleLines so view reflects session logs instantly
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(scanSession.consoleLines, id: \.self) { line in
                        Text(line)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(line.contains("[THREAT]") ? .red : .green)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
            .frame(maxHeight: 250)
            .background(Color.black)
            .cornerRadius(8)

            Spacer()

            // Cancel button: cancels the session task and navigation flags
            Button(action: handleCancel) {
                Text(scanSession.isScanning ? "Cancel Scan" : "Back")
                    .fontWeight(.semibold)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 32)
                    .background(scanSession.isScanning ? Color.red : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }

            // Hidden NavigationLink is not needed because we use navigationDestination on the root stack.
            // The ScanSession.finishScan() will set showResults = true to trigger presentation.
        }
        .padding()
        .background(Color(.systemBackground))
        .navigationTitle("Scanning")
    }

    // MARK: - Helpers

    private var clampedProgressFraction: Double {
        min(max(scanSession.progressFraction, 0.0), 1.0)
    }

    private func handleCancel() {
        // Cancel the session; cancelScan() clears flags so navigation will update.
        if scanSession.isScanning {
            scanSession.cancelScan()
        } else {
            // if not scanning, just reset and dismiss to be safe
            scanSession.reset()
            dismiss()
        }
    }

    private func startBugAnimation() {
        withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
            rotation = 360
        }
        Task {
            var index = 0
            while !Task.isCancelled && scanSession.isScanning {
                await MainActor.run {
                    bugColor = bugColors[index % bugColors.count]
                }
                index += 1
                try? await Task.sleep(nanoseconds: 800_000_000)
            }
        }
    }
}
