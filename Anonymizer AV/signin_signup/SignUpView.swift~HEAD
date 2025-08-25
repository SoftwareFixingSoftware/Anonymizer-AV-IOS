//
//  SignUpView.swift
//  Anonymizer AV
//
//  Created by gitiriku lucas mwangi on 18/08/2025.
//

import SwiftUI

struct SignUpView: View {
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showAlert = false
    @State private var alertMessage = ""
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image("app_logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .padding(.top, 24)

                Text("Create account")
                    .font(.title2.weight(.semibold))
                    .foregroundColor(.white)

                VStack(spacing: 12) {
                    TextField("Username", text: $username)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.systemBackground)))

                    TextField("Email", text: $email)
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.systemBackground)))

                    SecureField("Password", text: $password)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.systemBackground)))

                    SecureField("Confirm Password", text: $confirmPassword)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.systemBackground)))

                    Button(action: createAccountTapped) {
                        Text("Create Account")
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentCyan))
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.cardBackground))
                .padding(.horizontal)

                Text("Or sign up with")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button(action: {
                    // TODO: implement Google signup
                }) {
                    HStack {
                        Image("google_logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                        Text("Sign up with Google")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
                    .padding(.horizontal)
                }

                Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Text("Already have an account? Sign In")
                        .foregroundColor(.accentCyan)
                        .padding(.top, 8)
                }

                Spacer()
            }
            .padding(.bottom, 32)
            .background(Color.appBackground.ignoresSafeArea())
            .alert(isPresented: $showAlert) {
                Alert(title: Text("Error"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
            }
        }
    }

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
        presentationMode.wrappedValue.dismiss()
    }
}

struct SignUpView_Previews: PreviewProvider {
    static var previews: some View {
        SignUpView()
            .preferredColorScheme(.dark)
    }
}
