//
//  car_appApp.swift
//  car-app
//
//  Created by Ben Birch on 25/04/2026.
//

import SwiftUI
import SwiftData
import Supabase

@main
struct car_appApp: App {
    @Environment(\.scenePhase) private var scenePhase

    @State private var isLoggedIn = false
    @State private var hasResolvedInitialSession = false
    @AppStorage("local_onboarding_complete") private var hasCompletedOnboarding = false
    @AppStorage("pending_profile_payload_json") private var pendingProfilePayloadJSON = ""

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            Group {
                if !hasResolvedInitialSession {
                    SplashView()
                } else if isLoggedIn {
                    if hasCompletedOnboarding {
                        ContentView()
                    } else {
                        PostLoginOnboardingView { payload in
                            // Prepared and stored locally for future backend submission.
                            pendingProfilePayloadJSON = payload.jsonString ?? ""
                            hasCompletedOnboarding = true
                        }
                    }
                } else {
                    LoginView(isLoggedIn: $isLoggedIn)
                }
            }
            .task {
                // Restore existing session from Keychain on launch,
                // then keep listening for auth state changes (sign-out,
                // token revocation, etc.) to update the UI reactively.
                for await (event, session) in supabase.auth.authStateChanges {
                    switch event {
                    case .initialSession:
                        await validateSession(session)
                    case .signedIn, .tokenRefreshed, .userUpdated:
                        await validateSession(session)
                    case .signedOut, .passwordRecovery, .userDeleted:
                        await MainActor.run {
                            isLoggedIn = false
                            hasResolvedInitialSession = true
                        }
                    default:
                        break
                    }
                }
            }
            .onOpenURL { url in
                Task {
                    do {
                        _ = try await supabase.auth.session(from: url)
                        await validateCurrentSession()
                    } catch {
                        await invalidateSession()
                    }
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                Task {
                    await validateCurrentSession()
                }
            }
        }
        .modelContainer(sharedModelContainer)
    }

    @MainActor
    private func invalidateSession() async {
        try? await supabase.auth.signOut()
        isLoggedIn = false
        hasResolvedInitialSession = true
    }

    private func validateCurrentSession() async {
        let currentSession = try? await supabase.auth.session
        await validateSession(currentSession)
    }

    private func validateSession(_ session: Session?) async {
        guard let session, !session.isExpired else {
            await invalidateSession()
            return
        }

        do {
            _ = try await supabase.auth.user()
            await MainActor.run {
                isLoggedIn = true
                hasResolvedInitialSession = true
            }
        } catch {
            await invalidateSession()
        }
    }
}
