import SwiftUI

/// Safe QuarantinedFileRow
/// - Keeps same signature as your previous implementation to avoid call-site changes.
/// - Avoids nested Buttons by using .onTapGesture for the whole-card open action.
/// - Uses ShareLink on iOS 16+ when the quarantined file exists; otherwise calls onRestoreOrExport().
struct QuarantinedFileRow: View {
    let file: QuarantinedFile
    let onOpen: () -> Void
    let onRestoreOrExport: () -> Void
    let onDelete: () -> Void

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private var fileURL: URL {
        URL(fileURLWithPath: file.filePath)
    }

    private var fileExists: Bool {
        !file.filePath.isEmpty && FileManager.default.fileExists(atPath: file.filePath)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(file.fileName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text("Quarantined: \(Self.dateFormatter.string(from: file.dateQuarantined))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(file.classification)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.12)))
                    .foregroundColor(.secondary)
            }

            if let reason = file.reason, !reason.isEmpty {
                Text(reason)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            HStack {
                Spacer()

                // Export / Restore (ShareLink on iOS16+ when file exists)
                if #available(iOS 16.0, *) {
                    if fileExists {
                        ShareLink(item: fileURL) {
                            Label {
                                Text("Export")
                                    .font(.system(size: 13))
                            } icon: {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.08)))
                            .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Export \(file.fileName)")
                    } else {
                        // visually-disabled export
                        Text("Export")
                            .font(.system(size: 13))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.08)))
                            .foregroundColor(.gray)
                            .accessibilityLabel("Export not available")
                    }
                } else {
                    // pre-iOS16 fallback: call your handler
                    Button(action: { onRestoreOrExport() }) {
                        Text("Export")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.08)))
                    .foregroundColor(.blue)
                    .accessibilityLabel("Export \(file.fileName)")
                }

                // Delete button
                Button(action: {
                    onDelete()
                }) {
                    Text("🗑️ Delete")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.08)))
                .foregroundColor(.red)
                .accessibilityLabel("Delete \(file.fileName)")
                .padding(.leading, 8)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)))
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        // Make the whole card tappable without nesting Buttons
        .contentShape(Rectangle())
        .onTapGesture {
            // defensive: ensure file exists before opening preview (optional)
            onOpen()
        }
    }
}
