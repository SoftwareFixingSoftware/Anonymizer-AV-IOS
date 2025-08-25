//
//  SessionManager.swift
//  Anonymizer AV
//
//  Small centralized session helper using AppStorage.
//  Replace AppStorage with Keychain for production credential storage.
//

import Foundation
import SwiftUI

/// Simple session manager backed by @AppStorage for quick persistence.
final class SessionManager: ObservableObject {
    // Using AppStorage so the UI updates automatically when changed.
    @AppStorage("isLoggedIn") private var storedIsLoggedIn: Bool = false
    @AppStorage("userEmail") private var storedEmail: String = ""
    @AppStorage("userName") private var storedName: String = ""

    static let shared = SessionManager()

    private init() {}

    var isLoggedIn: Bool {
        get { storedIsLoggedIn }
        set { storedIsLoggedIn = newValue }
    }

    var userEmail: String {
        get { storedEmail }
        set { storedEmail = newValue }
    }

    var username: String {
        get { storedName }
        set { storedName = newValue }
    }

    func signIn(email: String, username: String? = nil) {
        self.userEmail = email
        if let u = username { self.username = u }
        self.isLoggedIn = true
    }

    func signOut() {
        self.isLoggedIn = false
        self.userEmail = ""
        self.username = ""
    }
}
