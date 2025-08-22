//
//  AnonymizerApp.swift
//  Anonymizer AV
//

import SwiftUI

@main
struct AnonymizerApp: App {
    // Persisted boolean that drives root content
    @AppStorage("isLoggedIn") private var isLoggedIn: Bool = false
    
    // Shared scanning session (environment object)
    @StateObject private var scanSession = ScanSession()

    var body: some Scene {
        WindowGroup {
            if isLoggedIn {
                MainTabView()
                    .environmentObject(scanSession)   // ✅ inject once at root
            } else {
                NavigationStack {
                    SignInView()
                }
                .accentColor(.cyan)
                .environmentObject(scanSession)      // ✅ also inject here
            }
        }
    }
}
