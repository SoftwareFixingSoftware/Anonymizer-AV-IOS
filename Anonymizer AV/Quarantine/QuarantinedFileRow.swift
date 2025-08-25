// QuarantinedFileRow.swift
import SwiftUI

struct QuarantinedFileRow: View {
    let file: QuarantinedFile
    let onRestore: () -> Void
    let onDelete: () -> Void

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // File Name and classification
            HStack {
                Text(file.fileName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Spacer()
                Text(file.classification)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.12)))
                    .foregroundColor(.secondary)
            }

            // Date Quarantined
            Text("Quarantined: \(Self.dateFormatter.string(from: file.dateQuarantined))")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Reason (optional)
            if let reason = file.reason, !reason.isEmpty {
                Text(reason)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Actions row
            HStack {
                Spacer()
                Button(action: onRestore) {
                    Text("♻️ Restore")
                        .font(.system(size: 13))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.blue.opacity(0.1))
                        )
                }

                Button(action: onDelete) {
                    Text("🗑️ Delete")
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.red.opacity(0.1))
                        )
                }
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
    }
}
