
//
//  AnonymizerApp.swift
//  Anonymizer AV
//
//  Created by ConversionBot on 2025-08-20.
//  App entry: chooses auth flow or main tabs based on persisted session.
//

import SwiftUI

@main
struct AnonymizerApp: App {
    // Simple persisted boolean that drives root content
    @AppStorage("isLoggedIn") private var isLoggedIn: Bool = false

    var body: some Scene {
        WindowGroup {
            if isLoggedIn {
                MainTabView()
            } else {
                // Present auth stack. NavigationStack allows pushing SignUp from SignIn.
                NavigationStack {
                    SignInView()
                }
                .accentColor(.cyan)
            }
        }
    }
}
