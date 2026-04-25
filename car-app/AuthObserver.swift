import Foundation
import Combine
import Supabase

@MainActor
final class AuthObserver: ObservableObject {
    @Published var isLoggedIn: Bool = false

    init() {
        Task { [weak self] in
            await self?.refreshSessionState()
        }
    }

    func refreshSessionState() async {
        do {
            let session = try await supabase.auth.session
            if session.isExpired {
                try? await supabase.auth.signOut()
                self.isLoggedIn = false
                return
            }

            // Verify the user with the backend; if deleted, this should throw
            do {
                _ = try await supabase.auth.user()
                self.isLoggedIn = true
            } catch {
                try? await supabase.auth.signOut()
                self.isLoggedIn = false
            }
        } catch {
            try? await supabase.auth.signOut()
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
