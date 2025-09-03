//
//  AnonymizerApp.swift
//  Anonymizer AV
//done updating account stuff

import SwiftUI

@main
struct AnonymizerApp: App {
    // Shared scanning session (environment object)
    @StateObject private var scanSession = ScanSession()

    var body: some Scene {
        WindowGroup {
            MainTabView()    
                .environmentObject(scanSession)
        }
    }
}
