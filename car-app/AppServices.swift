import Foundation
import Supabase

@MainActor
final class AppServices {
    static let shared = AppServices()

    let apiClient: APIClient
    let convoyService: ConvoyService
    let convoyStore: ConvoyStore
    let voiceStore: VoiceStore

    private init() {
        apiClient = APIClient(
            accessTokenProvider: {
                let session = try await supabase.auth.session
                return session.accessToken
            },
            refreshAuthSession: {
                let refreshed = try await supabase.auth.refreshSession()
                return refreshed.accessToken
            }
        )

        convoyService = ConvoyService(apiClient: apiClient)
        convoyStore = ConvoyStore(service: convoyService)
        voiceStore = VoiceStore.live(convoyService: convoyService)
    }
}
