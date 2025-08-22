// ------------------------------------------------------------
// Models.swift
// Shared models for scan results
// ------------------------------------------------------------

import Foundation

struct ScanResultItemModel: Identifiable {
    let id = UUID()
    let fileName: String
    let infected: Bool
    let fileURL: URL
    let category: String
    let threatName: String
}

func fileName(from url: URL) -> String {
    return url.lastPathComponent
}
