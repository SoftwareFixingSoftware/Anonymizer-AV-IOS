//  SignUpView.swift
//  Anonymizer AV
//
//  Created by gitiriku lucas mwangi on 18/08/2025.
//  Dark / pure-black card theme (OLED-friendly).
//

import SwiftUI

struct SignUpView: View {
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showAlert = false
    @State private var alertMessage = ""
    @Environment(\.dismiss) private var dismiss

    // Theme colors for true-black OLED look (match SignInView)
    private var bgBlack: Color { Color.black }
    private var cardBlack: Color { Color.black } // pure black card
    private var fieldBlack: Color { Color(red: 0.07, green: 0.07, blue: 0.07) } // slightly lighter for inputs
    private var strokeGray: Color { Color(red: 0.18, green: 0.18, blue: 0.18) }
    private var primaryText: Color { Color.white }
    private var secondaryText: Color { Color(red: 0.65, green: 0.65, blue: 0.65) }
    private var accentCyan: Color { Color(red: 0.00, green: 0.62, blue: 0.85) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Logo (template-friendly)
                if let ui = UIImage(named: "app_logo") {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 182, height: 132)
                        .padding(.top, 8)
                        .colorMultiply(.white)
                } else {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .foregroundColor(primaryText)
                        .padding(.top, 24)
                }

                Text("Create account")
                    .font(.title2.weight(.semibold))
                    .foregroundColor(primaryText)

                // Card
                VStack(spacing: 12) {
                    // Username
                    TextField("Username", text: $username)
                        .padding(14)
                        .background(fieldBlack)
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(strokeGray.opacity(0.30), lineWidth: 1))
                        .foregroundColor(primaryText)
                        .autocapitalization(.none)
                        .textInputAutocapitalization(.never)

                    // Email
                    TextField("Email", text: $email)
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                        .padding(14)
                        .background(fieldBlack)
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(strokeGray.opacity(0.30), lineWidth: 1))
                        .foregroundColor(primaryText)

                    // Password
                    SecureField("Password", text: $password)
                        .padding(14)
                        .background(fieldBlack)
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(strokeGray.opacity(0.30), lineWidth: 1))
                        .foregroundColor(primaryText)

                    // Confirm Password
                    SecureField("Confirm Password", text: $confirmPassword)
                        .padding(14)
                        .background(fieldBlack)
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(strokeGray.opacity(0.30), lineWidth: 1))
                        .foregroundColor(primaryText)

                    // Create Account button
                    Button(action: createAccountTapped) {
                        Text("Create Account")
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 10).fill(accentCyan))
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 16).fill(cardBlack))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(strokeGray.opacity(0.10), lineWidth: 0.5))
                .padding(.horizontal)

                Text("Or sign up with")
                    .font(.caption)
                    .foregroundColor(secondaryText)

                // Google signup placeholder
                Button(action: {
                    // TODO: implement Google signup
                }) {
                    HStack {
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
                        Text("Sign up with Google")
                            .foregroundColor(primaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 10).fill(cardBlack))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(strokeGray.opacity(0.18)))
                    .padding(.horizontal)
                }

                Button(action: {
                    dismiss()
                }) {
                    Text("Already have an account? Sign In")
                        .foregroundColor(accentCyan)
                        .padding(.top, 8)
                }

                Spacer()
            }
            .padding(.bottom, 32)
            .background(bgBlack.ignoresSafeArea())
            .alert(isPresented: $showAlert) {
                Alert(title: Text("Error"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Actions

    private func createAccountTapped() {
        // Local validation
        if username.trimmingCharacters(in: .whitespaces).isEmpty ||
            email.trimmingCharacters(in: .whitespaces).isEmpty ||
            password.isEmpty || confirmPassword.isEmpty {
            alertMessage = "Please fill in all fields."
            showAlert = true
            return
        }

        if password != confirmPassword {
            alertMessage = "Passwords do not match."
            showAlert = true
            return
        }

        // For MVP we just print and dismiss to SignIn.
        // Hook in real account creation API here.
        print("Account created: \(username) <\(email)>")
        dismiss()
    }
}

struct SignUpView_Previews: PreviewProvider {
    static var previews: some View {
        SignUpView()
            .preferredColorScheme(.dark)
            .previewDisplayName("Black Theme")
    }
}
