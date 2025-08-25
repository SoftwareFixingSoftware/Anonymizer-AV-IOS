//
//  SignInView.swift
//  Anonymizer AV
//
//  Created by gitiriku lucas mwangi on 18/08/2025.
//  Production-ready UI + persistence via SessionManager.
//

import SwiftUI

struct SignInView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var showAlert = false
    @State private var alertMessage = ""
    @ObservedObject private var session = SessionManager.shared

    var body: some View {
        GeometryReader { geometry in
            VStack {
                Spacer(minLength: 8)

                // Logo centered
                Image("app_logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .padding(.top, 12)

                Text("Welcome back")
                    .font(.title2.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.top, 8)

                // Card-like sign-in form
                VStack(spacing: 14) {
                    TextField("Email", text: $email)
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.systemBackground)))
                        .textInputAutocapitalization(.never)

                    SecureField("Password", text: $password)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.systemBackground)))

                    HStack {
                        Spacer()
                        Button(action: {
                            // TODO: Forgot password implementation
                        }) {
                            Text("Forgot Password?")
                                .font(.caption)
                                .foregroundColor(.accentCyan)
                        }
                    }

                    Button(action: signInTapped) {
                        HStack {
                            Image(systemName: "lock.fill")
                            Text("Sign In")
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentCyan))
                    }

                    HStack {
                        Rectangle().frame(height: 1).foregroundColor(.secondary).opacity(0.3)
                        Text("Or sign in with")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Rectangle().frame(height: 1).foregroundColor(.secondary).opacity(0.3)
                    }.padding(.vertical, 8)

                    Button(action: {
                        // TODO: Google Sign In hook
                    }) {
                        HStack {
                            Image("google_logo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                            Text("Sign in with Google")
                                .font(.subheadline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
                    }

                    NavigationLink(destination: SignUpView()) {
                        Text("Don't have an account? Sign Up")
                            .font(.footnote)
                            .foregroundColor(.accentCyan)
                            .padding(.top, 6)
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.cardBackground))
                .padding(.horizontal)
                .padding(.top, 12)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground.ignoresSafeArea())
            .alert(isPresented: $showAlert) {
                Alert(title: Text("Sign In Error"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
            }
        }
    }

    private func signInTapped() {
        // Basic validation only (replace with real auth)
        guard !email.trimmingCharacters(in: .whitespaces).isEmpty,
              !password.isEmpty else {
            alertMessage = "Please enter both email and password."
            showAlert = true
            return
        }

        // Simulate sign-in success and persist session
        // In production call your auth API and on success call:
        session.signIn(email: email, username: email.components(separatedBy: "@").first ?? "")
    }
}

struct SignInView_Previews: PreviewProvider {
    static var previews: some View {
        SignInView()
            .preferredColorScheme(.dark)
    }
}

