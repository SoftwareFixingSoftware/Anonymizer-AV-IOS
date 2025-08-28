//  SignInView.swift
//  Anonymizer AV
//
//  Created by gitiriku lucas mwangi on 18/08/2025.
//  Dark / pure-black card theme + hidden reviewer creds.
//  Reviewer credentials are accepted by logic but NOT shown anywhere in the UI.

import SwiftUI

struct SignInView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var showAlert = false
    @State private var alertMessage = ""
    @ObservedObject private var session = SessionManager.shared

    // Reviewer credentials (kept in code for test/review only).
    // NOTE: these are intentionally NOT shown anywhere in the UI.
    // Only share them privately with the reviewer if you need to.
    private let reviewerEmail = "test@example.com"
    private let reviewerPassword = "1234"

    // Theme colors for true-black OLED look
    private var bgBlack: Color { Color.black }
    private var cardBlack: Color { Color.black } // pure black card
    private var fieldBlack: Color { Color(red: 0.07, green: 0.07, blue: 0.07) } // slightly lighter for inputs
    private var strokeGray: Color { Color(red: 0.18, green: 0.18, blue: 0.18) }
    private var primaryText: Color { Color.white }
    private var secondaryText: Color { Color(red: 0.65, green: 0.65, blue: 0.65) }
    private var accentCyan: Color { Color(red: 0.00, green: 0.62, blue: 0.85) }

    var body: some View {
        GeometryReader { geometry in
            VStack {
                Spacer(minLength: 12)

                // Logo (use template or fallback)
                if let ui = UIImage(named: "app_logo") {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 182, height: 132)
                        .padding(.top, 8)
                        .colorMultiply(.white)
                } else {
                    Image(systemName: "lock.shield.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                        .foregroundColor(primaryText)
                        .padding(.top, 8)
                }

                Text("Welcome back")
                    .font(.title2.weight(.semibold))
                    .foregroundColor(primaryText)
                    .padding(.top, 8)

                // Card-like sign-in form (pure black)
                VStack(spacing: 14) {
                    // Email field
                    TextField("Email", text: $email)
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                        .padding(14)
                        .background(fieldBlack)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(strokeGray.opacity(0.30), lineWidth: 1)
                        )
                        .foregroundColor(primaryText)
                        .textInputAutocapitalization(.never)

                    // Password field
                    SecureField("Password", text: $password)
                        .padding(14)
                        .background(fieldBlack)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(strokeGray.opacity(0.30), lineWidth: 1)
                        )
                        .foregroundColor(primaryText)

                    HStack {
                        Spacer()
                        Button(action: {
                            // TODO: implement forgot password flow
                        }) {
                            Text("Forgot Password?")
                                .font(.caption)
                                .foregroundColor(accentCyan)
                        }
                    }

                    // Sign in button
                    Button(action: signInTapped) {
                        HStack {
                            Image(systemName: "lock.fill")
                            Text("Sign In")
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 10).fill(accentCyan))
                    }

                    // Divider text
                    HStack {
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(strokeGray.opacity(0.25))
                        Text("Or sign in with")
                            .font(.caption)
                            .foregroundColor(secondaryText)
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(strokeGray.opacity(0.25))
                    }
                    .padding(.vertical, 8)

                    // Google sign-in placeholder
                    Button(action: {
                        // TODO: Google Sign In hook
                    }) {
                        HStack(spacing: 10) {
                            if let google = UIImage(named: "google_logo") {
                                Image(uiImage: google)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 20, height: 20)
                            } else {
                                Image(systemName: "globe")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 18, height: 18)
                                    .foregroundColor(secondaryText)
                            }
                            Text("Sign in with Google")
                                .font(.subheadline)
                                .foregroundColor(primaryText)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 10).fill(cardBlack))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(strokeGray.opacity(0.18)))
                    }

                    NavigationLink(destination: SignUpView()) {
                        Text("Don't have an account? Sign Up")
                            .font(.footnote)
                            .foregroundColor(accentCyan)
                            .padding(.top, 6)
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 16).fill(cardBlack)) // pure black card
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(strokeGray.opacity(0.10), lineWidth: 0.5)
                )
                .padding(.horizontal)
                .padding(.top, 14)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(bgBlack.ignoresSafeArea())
            .alert(isPresented: $showAlert) {
                Alert(title: Text("Sign In"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
            }
        }
        .preferredColorScheme(.dark) // force dark appearance for preview & runtime look
    }

    // MARK: - Actions

    private func signInTapped() {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

        // Hidden reviewer shortcut: accepted but not shown in UI.
        if cleanEmail.lowercased() == reviewerEmail.lowercased() && password == reviewerPassword {
            session.signIn(email: reviewerEmail, username: reviewerEmail.components(separatedBy: "@").first ?? "")
            return
        }

        // Normal validation flow (no server in this build)
        guard !cleanEmail.isEmpty, !password.isEmpty else {
            alertMessage = "Please enter both email and password."
            showAlert = true
            return
        }

        // Simulate sign-in success (replace with real auth later)
        session.signIn(email: cleanEmail, username: cleanEmail.components(separatedBy: "@").first ?? "")
    }
}

struct SignInView_Previews: PreviewProvider {
    static var previews: some View {
        SignInView()
            .preferredColorScheme(.dark)
            .previewDisplayName("Black Theme")
    }
}
