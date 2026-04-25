import Foundation
import Combine
import Supabase

@MainActor
final class AuthObserver: ObservableObject {
    @Published var isLoggedIn: Bool = false

    private var authCancellable: AnyCancellable?

    init() {
        // Initial check on init
        Task { [weak self] in
            await self?.refreshSessionState()
        }

        // Subscribe to auth state changes
        authCancellable = supabase.auth.authStateChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self else { return }
                switch event.event {
                case .initialSession, .signedIn, .tokenRefreshed:
                    Task { await self.refreshSessionState() }
                case .signedOut, .userUpdated, .passwordRecovery:
                    Task { await self.refreshSessionState() }
                default:
                    break
                }
            }
    }

    func refreshSessionState() async {
        do {
            if let session = try await supabase.auth.session {
                // Validate the user still exists on the server
                _ = try await supabase.auth.getUser()
                self.isLoggedIn = (session.user != nil)
            } else {
                self.isLoggedIn = false
            }
        } catch {
            // Any error fetching session/user -> sign out locally and mark logged out
            do { try await supabase.auth.signOut() } catch { /* ignore */ }
            self.isLoggedIn = false
        }
    }

    func handleOpenURL(_ url: URL) {
        Task {
            do {
                try await supabase.auth.session(from: url)
                await refreshSessionState()
            } catch {
                await refreshSessionState()
            }
        }
    }
}
