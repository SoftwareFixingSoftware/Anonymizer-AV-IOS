import SwiftUI

struct SettingsView: View {
    @ObservedObject private var session = SessionManager.shared
    @ObservedObject private var heuristics = HeuristicsManager.shared

    // Alerts
    @State private var showClearConfirm = false
    @State private var showLogoutConfirm = false

    // Accent / colors (match earlier theme)
    private var bgBlack: Color { Color.black }
    private var primaryText: Color { Color.white }
    private var dividerColor: Color { Color(white: 0.3) }
    private var accentCyan: Color { Color(red: 0.00, green: 0.62, blue: 0.85) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Logo area
                Group {
                    if let ui = UIImage(named: "anonymizer_av_logo") {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 150)
                            .padding(.top, 16)
                            .accessibilityHidden(true)
                    } else if let ui = UIImage(named: "app_logo") {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 150)
                            .padding(.top, 16)
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: "shield.lefthalf.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 120)
                            .foregroundColor(primaryText)
                            .padding(.top, 16)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal)

                // Account Details
                VStack(alignment: .leading, spacing: 6) {
                    Text("Account Details")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(primaryText)
                        .padding(.bottom, 8)

                    Text(session.username.isEmpty ? "Username" : session.username)
                        .foregroundColor(primaryText)
                        .font(.system(size: 16))
                        .padding(.bottom, 2)

                    Text(session.userEmail.isEmpty ? "Email" : session.userEmail)
                        .foregroundColor(primaryText)
                        .font(.system(size: 16))
                        .padding(.bottom, 16)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

                Rectangle().fill(dividerColor).frame(height: 1).padding(.horizontal)

                // Protection Settings - BOUND to HeuristicsManager via custom Binding
                VStack(alignment: .leading, spacing: 8) {
                    Text("Protection Settings")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(primaryText)
                        .padding(.bottom, 8)

                    Toggle(isOn: Binding(get: {
                        heuristics.isEnabled
                    }, set: { newVal in
                        // Use manager API to change — preserves encapsulation
                        Task { @MainActor in
                            heuristics.setEnabled(newVal)
                        }
                    })) {
                        Text("Enable Heuristic Scans")
                            .foregroundColor(primaryText)
                    }
                    .toggleStyle(SwitchToggleStyle(tint: accentCyan))
                    .padding(.vertical, 4)
                }
                .padding(.horizontal)

                Rectangle().fill(dividerColor).frame(height: 1).padding(.vertical, 16).padding(.horizontal)

                // Actions
                VStack(alignment: .leading, spacing: 8) {
                    Text("Actions")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(primaryText)
                        .padding(.bottom, 8)

                    Button(action: {
                        showClearConfirm = true
                    }) {
                        Text("Clear Scan History")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .foregroundColor(primaryText)
                            .background(Color.clear)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal)

                    Button(action: {
                        showLogoutConfirm = true
                    }) {
                        Text("Logout")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .foregroundColor(primaryText)
                            .background(Color.clear)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 24)
            }
            .padding(.bottom, 24)
        }
        .background(bgBlack.ignoresSafeArea())
        .confirmationDialog("Clear scan history?", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("Clear", role: .destructive) {
                ScanLogManager.clearLogs()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove saved scan logs.")
        }
        .alert("Logout", isPresented: $showLogoutConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Logout", role: .destructive) {
                SessionManager.shared.signOut()
            }
        } message: {
            Text("Are you sure you want to logout?")
        }
        .onAppear {
            // nothing else — heuristics state is managed by HeuristicsManager
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .preferredColorScheme(.dark)
    }
}
