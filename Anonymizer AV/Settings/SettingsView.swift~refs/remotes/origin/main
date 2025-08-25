//
//  SettingsView.swift
//  Anonymizer AV
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject private var session = SessionManager.shared
    @State private var path: [String] = []
    
    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 20) {
                    
                    // Profile Card (using same QuarantineCard style)
                    QuarantineCard {
                        HStack(spacing: 16) {
                            Image("app_logo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.username.isEmpty ? "User" : session.username)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text(session.userEmail.isEmpty ? "Not set" : session.userEmail)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                    }
                    
                    // Settings Options (future-proof expandable list)
                    VStack(spacing: 12) {
                        NavigationLink("Account Details") {
                            AccountDetailsView()
                        }
                        .buttonStyle(SettingsRowStyle())
                        
                        NavigationLink("Privacy & Security") {
                            PrivacyView()
                        }
                        .buttonStyle(SettingsRowStyle())
                        
                        NavigationLink("Notifications") {
                            NotificationsView()
                        }
                        .buttonStyle(SettingsRowStyle())
                    }
                    .padding(.horizontal)
                    
                    // Sign Out Button
                    Button {
                        session.signOut()
                    } label: {
                        Text("Sign Out")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    
                    Spacer()
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Settings")
        }
    }
}

// MARK: - Row Button Style (matches Dashboard theme)
struct SettingsRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.18), lineWidth: 0.5)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}

// MARK: - Placeholder Views
struct AccountDetailsView: View {
    var body: some View {
        Text("Account Details").navigationTitle("Account")
    }
}

struct PrivacyView: View {
    var body: some View {
        Text("Privacy & Security").navigationTitle("Privacy")
    }
}

struct NotificationsView: View {
    var body: some View {
        Text("Notifications").navigationTitle("Notifications")
    }
}

// MARK: - Preview
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
