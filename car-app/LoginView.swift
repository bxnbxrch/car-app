//
//  LoginView.swift
//  car-app
//
//  Created by OpenAI on 25/04/2026.
//

import SwiftUI
import AuthenticationServices
import Supabase

struct LoginView: View {
    @Binding var isLoggedIn: Bool

    private enum Mode { case signIn, signUp, awaitingVerification }

    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var authSession: ASWebAuthenticationSession?

    private let presentationContextProvider = WebAuthenticationPresentationContextProvider()

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
                                .foregroundStyle(AppTheme.textPrimary)

                            Text(mode == .signIn
                                 ? "Sign in to find drives, locations, fuel prices, and your car data."
                                 : "Enter your details below to get started with Driveout.")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.textSecondary)

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
                                .background(primaryActionEnabled ? AppTheme.brandAccent : AppTheme.buttonDisabled)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.buttonCornerRadius))
                            }
                            .disabled(!primaryActionEnabled || isLoading)

                            googleDivider

                            Button(action: signInWithGoogle) {
                                HStack(spacing: 12) {
                                    Image("google-logo")
                                        .renderingMode(.original)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 20, height: 20)

                                    Text("Continue with Google")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(AppTheme.googleButtonBackground)
                                .foregroundStyle(AppTheme.textPrimary)
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppTheme.buttonCornerRadius)
                                        .stroke(AppTheme.borderSubtle, lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.buttonCornerRadius))
                            }
                            .disabled(isLoading)

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
                                        .foregroundStyle(AppTheme.brandAccent)
                                }
                                Spacer()
                            }
                        }
                    }
                    .padding(24)
                    .background(AppTheme.surfaceCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius)
                            .stroke(AppTheme.borderSubtle, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))

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
                    password: password,
                    redirectTo: URL(string: "driveout://auth-callback")
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

    private func signInWithGoogle() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let redirectURL = URL(string: "driveout://auth-callback")!
                let oauthURL = try supabase.auth.getOAuthSignInURL(
                    provider: .google,
                    redirectTo: redirectURL
                )

                await MainActor.run {
                    startWebAuthentication(with: oauthURL)
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    private func startWebAuthentication(with url: URL) {
        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: "driveout"
        ) { callbackURL, error in
            Task { @MainActor in
                if let authError = error as? ASWebAuthenticationSessionError,
                   authError.code == .canceledLogin {
                    isLoading = false
                    return
                }

                guard let callbackURL else {
                    errorMessage = error?.localizedDescription ?? "Google sign-in failed."
                    isLoading = false
                    return
                }

                do {
                    try await supabase.auth.session(from: callbackURL)
                    isLoggedIn = true
                    isLoading = false
                } catch {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }

        session.presentationContextProvider = presentationContextProvider
        session.prefersEphemeralWebBrowserSession = false
        authSession = session
        session.start()
    }

    private var verificationPendingCard: some View {
        VStack(spacing: 20) {
            Image(systemName: "envelope.badge.shield.half.filled")
                .font(.system(size: 48))
                .foregroundStyle(AppTheme.brandAccent)

            Text("Check your inbox")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(AppTheme.textPrimary)

            Text("We've sent a verification link to\n**\(email)**. Click it to activate your account, then sign in.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
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
                    .background(AppTheme.brandAccent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.buttonCornerRadius))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var googleDivider: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(AppTheme.borderSubtle)
                .frame(height: 1)

            Text("or")
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)

            Rectangle()
                .fill(AppTheme.borderSubtle)
                .frame(height: 1)
        }
    }

    private var backgroundView: some View {
        ZStack {
            AppTheme.appBackground

            Circle()
                .fill(AppTheme.brandAccentGlow)
                .frame(width: 320)
                .blur(radius: 40)
                .offset(x: -120, y: -220)

            Circle()
                .fill(AppTheme.glassHighlight)
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
                .shadow(color: Color.black.opacity(0.18), radius: 18, y: 8)

            Text("Sign in to your Driveout account")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
        }
    }

    private func inputField(title: String, text: Binding<String>, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(AppTheme.brandAccent)
                .frame(width: 20)

            TextField(title, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)
                .foregroundStyle(AppTheme.textPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(AppTheme.surfaceField)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.fieldCornerRadius)
                .stroke(AppTheme.borderAccent, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.fieldCornerRadius))
    }

    private func secureInputField(title: String, text: Binding<String>, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(AppTheme.brandAccent)
                .frame(width: 20)

            SecureField(title, text: text)
                .foregroundStyle(AppTheme.textPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(AppTheme.surfaceField)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.fieldCornerRadius)
                .stroke(AppTheme.borderAccent, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.fieldCornerRadius))
    }

    private var logoImageName: String {
        "driveout-logo"
    }
}

final class WebAuthenticationPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let windowScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }

        if let keyWindow = windowScenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) {
            return keyWindow
        }

        if let firstWindow = windowScenes.flatMap(\.windows).first {
            return firstWindow
        }

        return ASPresentationAnchor(windowScene: windowScenes.first!)
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
