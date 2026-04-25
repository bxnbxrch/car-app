//
//  LoginView.swift
//  car-app
//
//  Created by OpenAI on 25/04/2026.
//

import SwiftUI
import Supabase

struct LoginView: View {
    @Environment(\.colorScheme) private var colorScheme

    @Binding var isLoggedIn: Bool

    private enum Mode { case signIn, signUp, awaitingVerification }

    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundView
                    .ignoresSafeArea()

                VStack(spacing: 28) {
                    Spacer(minLength: 32)

                    brandHeader

                    VStack(alignment: .leading, spacing: 18) {
                        if mode == .awaitingVerification {
                            verificationPendingCard
                        } else {
                            Text(mode == .signIn ? "Welcome back" : "Create an account")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(primaryTextColor)

                            Text(mode == .signIn
                                 ? "Sign in to find drives, locations, fuel prices, and your car data."
                                 : "Enter your details below to get started with Driveout.")
                                .font(.subheadline)
                                .foregroundStyle(secondaryTextColor)

                            VStack(spacing: 14) {
                                inputField(
                                    title: "Email",
                                    text: $email,
                                    systemImage: "envelope"
                                )

                                secureInputField(
                                    title: "Password",
                                    text: $password,
                                    systemImage: "lock"
                                )

                                if mode == .signUp {
                                    secureInputField(
                                        title: "Confirm Password",
                                        text: $confirmPassword,
                                        systemImage: "lock.shield"
                                    )

                                    if !confirmPassword.isEmpty && password != confirmPassword {
                                        Text("Passwords do not match")
                                            .font(.caption)
                                            .foregroundStyle(.red)
                                    }
                                }
                            }

                            Button(action: mode == .signIn ? signIn : signUp) {
                                Group {
                                    if isLoading {
                                        ProgressView()
                                            .tint(.white)
                                    } else {
                                        Text(mode == .signIn ? "Sign In" : "Create Account")
                                            .fontWeight(.semibold)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(primaryActionEnabled ? brandBlue : disabledButtonColor)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                            }
                            .disabled(!primaryActionEnabled || isLoading)

                            if let errorMessage {
                                Text(errorMessage)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity)
                            }

                            HStack {
                                Spacer()
                                Button(action: toggleMode) {
                                    Text(mode == .signIn ? "Don't have an account? Sign up" : "Already have an account? Sign in")
                                        .font(.footnote)
                                        .foregroundStyle(brandBlue)
                                }
                                Spacer()
                            }
                        }
                    }
                    .padding(24)
                    .background(cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28)
                            .stroke(cardBorderColor, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 28))

                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var primaryActionEnabled: Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty && !password.isEmpty else { return false }
        if mode == .signUp {
            return !confirmPassword.isEmpty && password == confirmPassword
        }
        return true
    }

    private func toggleMode() {
        errorMessage = nil
        confirmPassword = ""
        password = ""
        mode = mode == .signIn ? .signUp : .signIn
    }

    private func signIn() {
        guard primaryActionEnabled else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await supabase.auth.signIn(
                    email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: password
                )
                await MainActor.run { isLoggedIn = true }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    private func signUp() {
        guard primaryActionEnabled else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await supabase.auth.signUp(
                    email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: password
                )
                await MainActor.run {
                    isLoading = false
                    mode = .awaitingVerification
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    private var verificationPendingCard: some View {
        VStack(spacing: 20) {
            Image(systemName: "envelope.badge.shield.half.filled")
                .font(.system(size: 48))
                .foregroundStyle(brandBlue)

            Text("Check your inbox")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(primaryTextColor)

            Text("We've sent a verification link to\n**\(email)**. Click it to activate your account, then sign in.")
                .font(.subheadline)
                .foregroundStyle(secondaryTextColor)
                .multilineTextAlignment(.center)

            Button(action: {
                mode = .signIn
                errorMessage = nil
                password = ""
                confirmPassword = ""
            }) {
                Text("Back to Sign In")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(brandBlue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var backgroundView: some View {
        ZStack {
            LinearGradient(
                colors: backgroundGradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(brandBlue.opacity(colorScheme == .dark ? 0.22 : 0.12))
                .frame(width: 320)
                .blur(radius: 40)
                .offset(x: -120, y: -220)

            Circle()
                .fill(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.3))
                .frame(width: 280)
                .blur(radius: 60)
                .offset(x: 140, y: -260)
        }
    }

    private var brandHeader: some View {
        VStack(spacing: 18) {
            Image(logoImageName)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 320)
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 18, y: 8)

            Text("Sign in to your Driveout account")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(secondaryTextColor)
        }
    }

    private func inputField(title: String, text: Binding<String>, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(brandBlue)
                .frame(width: 20)

            TextField(title, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)
                .foregroundStyle(primaryTextColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(fieldBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(fieldBorderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func secureInputField(title: String, text: Binding<String>, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(brandBlue)
                .frame(width: 20)

            SecureField(title, text: text)
                .foregroundStyle(primaryTextColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(fieldBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(fieldBorderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var backgroundGradientColors: [Color] {
        colorScheme == .dark
            ? [Color(red: 0.02, green: 0.03, blue: 0.06), Color(red: 0.06, green: 0.08, blue: 0.12), .black]
            : [Color(red: 0.95, green: 0.97, blue: 1.0), .white, Color(red: 0.9, green: 0.94, blue: 0.99)]
    }

    private var cardBackground: AnyShapeStyle {
        colorScheme == .dark
            ? AnyShapeStyle(Color.white.opacity(0.06))
            : AnyShapeStyle(Color.white.opacity(0.88))
    }

    private var fieldBackground: AnyShapeStyle {
        colorScheme == .dark
            ? AnyShapeStyle(Color.white.opacity(0.08))
            : AnyShapeStyle(Color.white.opacity(0.95))
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : Color(red: 0.08, green: 0.1, blue: 0.14)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.6)
    }

    private var cardBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }

    private var fieldBorderColor: Color {
        colorScheme == .dark ? brandBlue.opacity(0.24) : brandBlue.opacity(0.18)
    }

    private var disabledButtonColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.18)
    }

    private var brandBlue: Color {
        Color(red: 0.05, green: 0.5, blue: 1.0)
    }

    private var brandBlueBright: Color {
        Color(red: 0.11, green: 0.78, blue: 1.0)
    }

    private var logoImageName: String {
        "driveout-logo"
    }
}

#Preview("Light") {
    LoginView(isLoggedIn: .constant(false))
        .preferredColorScheme(.light)
}
#Preview("Dark") {
    LoginView(isLoggedIn: .constant(false))
        .preferredColorScheme(.dark)
}
