import Foundation
import SwiftUI
import Combine
import Supabase

enum APIClientError: LocalizedError {
    case invalidResponse
    case unauthorized
    case serverError(statusCode: Int, payload: APIErrorPayload?, retryAfter: TimeInterval?)
    case decodingError

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response."
        case .unauthorized:
            return "Session expired. Please sign in again."
        case .serverError(let statusCode, let payload, _):
            if let message = payload?.message, !message.isEmpty {
                return message
            }
            return "Request failed with status \(statusCode)."
        case .decodingError:
            return "The response could not be decoded."
        }
    }
}

struct APIEndpoint {
    let path: String
    let method: String
    let queryItems: [URLQueryItem]

    init(path: String, method: String = "GET", queryItems: [URLQueryItem] = []) {
        self.path = path
        self.method = method
        self.queryItems = queryItems
    }
}

actor APIClient {
    private let baseURL: URL
    private let session: URLSession
    private let accessTokenProvider: @Sendable () async throws -> String
    private let refreshAuthSession: @Sendable () async throws -> String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        baseURL: URL = URL(string: "https://api.driveout.uk")!,
        session: URLSession = .shared,
        accessTokenProvider: @escaping @Sendable () async throws -> String,
        refreshAuthSession: @escaping @Sendable () async throws -> String
    ) {
        self.baseURL = baseURL
        self.session = session
        self.accessTokenProvider = accessTokenProvider
        self.refreshAuthSession = refreshAuthSession

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            if let date = ISO8601DateFormatter.fractionalSeconds.date(from: value) {
                return date
            }

            if let date = ISO8601DateFormatter.standard.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date format: \(value)")
        }
        self.decoder = decoder
    }

    func request<T: Decodable>(_ endpoint: APIEndpoint) async throws -> T {
        let data = try await send(endpoint: endpoint, bodyData: nil)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIClientError.decodingError
        }
    }

    func requestNoContent(_ endpoint: APIEndpoint) async throws {
        _ = try await send(endpoint: endpoint, bodyData: nil)
    }

    func request<T: Decodable, B: Encodable>(_ endpoint: APIEndpoint, body: B) async throws -> T {
        let bodyData = try encoder.encode(body)
        let data = try await send(endpoint: endpoint, bodyData: bodyData)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIClientError.decodingError
        }
    }

    func requestNoContent<B: Encodable>(_ endpoint: APIEndpoint, body: B) async throws {
        let bodyData = try encoder.encode(body)
        _ = try await send(endpoint: endpoint, bodyData: bodyData)
    }

    private func send(endpoint: APIEndpoint, bodyData: Data?) async throws -> Data {
        let token = try await accessTokenProvider()
        do {
            return try await perform(endpoint: endpoint, token: token, bodyData: bodyData)
        } catch APIClientError.unauthorized {
            let refreshedToken = try await refreshAuthSession()
            return try await perform(endpoint: endpoint, token: refreshedToken, bodyData: bodyData)
        }
    }

    private func perform(endpoint: APIEndpoint, token: String, bodyData: Data?) async throws -> Data {
        let request = try buildRequest(endpoint: endpoint, token: token, bodyData: bodyData)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }

        if (200...299).contains(httpResponse.statusCode) {
            return data
        }

        let payload = try? decoder.decode(APIErrorPayload.self, from: data)
        if httpResponse.statusCode == 401 {
            throw APIClientError.unauthorized
        }

        if httpResponse.statusCode == 410,
           payload?.error == "invite_expired" {
            throw APIClientError.serverError(statusCode: 410, payload: payload, retryAfter: nil)
        }

        let retryAfter = parseRetryAfter(from: httpResponse)
        throw APIClientError.serverError(
            statusCode: httpResponse.statusCode,
            payload: payload,
            retryAfter: retryAfter
        )
    }

    private func buildRequest(endpoint: APIEndpoint, token: String, bodyData: Data?) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(endpoint.path), resolvingAgainstBaseURL: false) else {
            throw APIClientError.invalidResponse
        }

        if !endpoint.queryItems.isEmpty {
            components.queryItems = endpoint.queryItems
        }

        guard let url = components.url else {
            throw APIClientError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        if let bodyData {
            request.httpBody = bodyData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return request
    }

    private func parseRetryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let headerValue = response.value(forHTTPHeaderField: "Retry-After") else {
            return nil
        }

        if let seconds = TimeInterval(headerValue) {
            return max(0, seconds)
        }

        return nil
    }
}

private enum EmptyRequestBody: Encodable {
    case value
}

struct CreateConvoyRequest: Encodable {
    let name: String
    let description: String?
    let relayRegion: String?

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case relayRegion = "relay_region"
    }
}

struct JoinConvoyRequest: Encodable {
    let token: String?
    let code: String?
}

struct CreateInviteRequest: Encodable {
    let type: InviteType
    let targetUserId: UUID?
    let maxUses: Int?
    let expiresInSeconds: Int?
    // Encodes as camelCase by default — matches what the backend destructures.
}

struct InviteRespondRequest: Encodable {
    let action: String
}

struct AcceptInviteRequest: Encodable {
    let token: String?
    let code: String?
}

struct RelayConnectRequest: Encodable {
    let convoyId: UUID
    let deviceUUID: String

    enum CodingKeys: String, CodingKey {
        case convoyId
        case deviceUUID
    }
}

struct LocationUpdateRequest: Encodable {
    let convoyId: UUID
    let latitude: Double
    let longitude: Double
    let speed: Double?

    enum CodingKeys: String, CodingKey {
        case convoyId
        case latitude
        case longitude
        case speed
    }
}

struct PresenceUpdateRequest: Encodable {
    let convoyId: UUID
    let listening: Bool
    let muted: Bool
    let lastAudioReceived: Date?
}

struct UpdateMemberRoleRequest: Encodable {
    let role: MemberRole
}

struct UpdateMemberRolePayload: Decodable {
    let membership: ConvoyMembership
}

final class ConvoyService {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func listConvoys() async throws -> [Convoy] {
        try await apiClient.request(APIEndpoint(path: "api/convoys"))
    }

    func convoyDetails(id: UUID) async throws -> ConvoyDetailPayload {
        try await apiClient.request(APIEndpoint(path: "api/convoys/\(id.uuidString)"))
    }

    func convoyMembers(id: UUID) async throws -> [ConvoyMember] {
        let payload: ConvoyMembersPayload = try await apiClient.request(APIEndpoint(path: "api/convoys/\(id.uuidString)/members"))
        return payload.members
    }

    func createConvoy(name: String, description: String?, relayRegion: String?) async throws -> Convoy {
        let requestBody = CreateConvoyRequest(name: name, description: description, relayRegion: relayRegion)
        return try await apiClient.request(APIEndpoint(path: "api/convoys", method: "POST"), body: requestBody)
    }

    func joinConvoy(id: UUID, token: String?, code: String?) async throws {
        let requestBody = JoinConvoyRequest(token: token, code: code)
        try await apiClient.requestNoContent(APIEndpoint(path: "api/convoys/\(id.uuidString)/join", method: "POST"), body: requestBody)
    }

    func leaveConvoy(id: UUID) async throws -> LeaveConvoyResult {
        try await apiClient.request(APIEndpoint(path: "api/convoys/\(id.uuidString)/leave", method: "POST"), body: EmptyRequestBody.value)
    }

    func endConvoy(id: UUID) async throws {
        try await apiClient.requestNoContent(APIEndpoint(path: "api/convoys/\(id.uuidString)/end", method: "POST"), body: EmptyRequestBody.value)
    }

    func createInvite(convoyId: UUID, request: CreateInviteRequest) async throws -> ConvoyInvite {
        try await apiClient.request(APIEndpoint(path: "api/convoys/\(convoyId.uuidString)/invites", method: "POST"), body: request)
    }

    func listInvites(convoyId: UUID) async throws -> [ConvoyInvite] {
        let payload: ConvoyInvitesPayload = try await apiClient.request(APIEndpoint(path: "api/convoys/\(convoyId.uuidString)/invites"))
        return payload.invites
    }

    func revokeInvite(convoyId: UUID, inviteId: UUID) async throws {
        try await apiClient.requestNoContent(
            APIEndpoint(path: "api/convoys/\(convoyId.uuidString)/invites/\(inviteId.uuidString)/revoke", method: "POST"),
            body: EmptyRequestBody.value
        )
    }

    func acceptInvite(token: String?, code: String?) async throws -> InviteAcceptanceResult {
        let body = AcceptInviteRequest(token: token, code: code)
        return try await apiClient.request(APIEndpoint(path: "api/convoys/invites/accept", method: "POST"), body: body)
    }

    func respondToInvite(inviteId: UUID, accepted: Bool) async throws {
        let body = InviteRespondRequest(action: accepted ? "accept" : "decline")
        try await apiClient.requestNoContent(APIEndpoint(path: "api/convoys/invites/\(inviteId.uuidString)/respond", method: "POST"), body: body)
    }

    func connectRelay(convoyId: UUID, deviceUUID: String) async throws -> ConnectRelayResponse {
        let body = RelayConnectRequest(convoyId: convoyId, deviceUUID: deviceUUID)
        return try await apiClient.request(APIEndpoint(path: "api/convoy/connect", method: "POST"), body: body)
    }

    func updateMemberRole(convoyId: UUID, userId: UUID, role: MemberRole) async throws -> ConvoyMembership {
        let body = UpdateMemberRoleRequest(role: role)
        let payload: UpdateMemberRolePayload = try await apiClient.request(
            APIEndpoint(path: "api/convoys/\(convoyId.uuidString)/members/\(userId.uuidString)/role", method: "POST"),
            body: body
        )
        return payload.membership
    }

    func removeMember(convoyId: UUID, userId: UUID) async throws {
        try await apiClient.requestNoContent(
            APIEndpoint(path: "api/convoys/\(convoyId.uuidString)/members/\(userId.uuidString)/remove", method: "POST"),
            body: EmptyRequestBody.value
        )
    }

    func convoyLocations(id: UUID) async throws -> [ConvoyLocation] {
        let payload: ConvoyLocationsPayload = try await apiClient.request(APIEndpoint(path: "api/convoys/\(id.uuidString)/locations"))
        return payload.locations
    }

    func convoyPresence(id: UUID) async throws -> [ConvoyPresence] {
        let payload: ConvoyPresencePayload = try await apiClient.request(APIEndpoint(path: "api/convoys/\(id.uuidString)/presence"))
        return payload.presence
    }

    func updateLocation(convoyId: UUID, latitude: Double, longitude: Double, speed: Double?) async throws {
        let body = LocationUpdateRequest(convoyId: convoyId, latitude: latitude, longitude: longitude, speed: speed)
        try await apiClient.requestNoContent(APIEndpoint(path: "api/location/update", method: "POST"), body: body)
    }

    func updatePresence(convoyId: UUID, listening: Bool, muted: Bool, lastAudioReceived: Date?) async throws {
        let body = PresenceUpdateRequest(convoyId: convoyId, listening: listening, muted: muted, lastAudioReceived: lastAudioReceived)
        try await apiClient.requestNoContent(APIEndpoint(path: "api/presence/update", method: "POST"), body: body)
    }
}

@MainActor
final class ConvoyStore: ObservableObject {
    @Published var convoys: [Convoy] = []
    @Published var selectedConvoy: Convoy?
    @Published var membership: ConvoyMembership?
    @Published var summary: ConvoySummary?
    @Published var members: [ConvoyMember] = []
    @Published var invites: [ConvoyInvite] = []
    @Published var locations: [ConvoyLocation] = []
    @Published var presence: [ConvoyPresence] = []
    @Published var isLoading = false
    @Published var isSubmitting = false
    @Published var errorMessage: String?
    @Published var infoMessage: String?
    @Published var lastInviteSecret: String?
    @Published var navigationConvoyID: UUID?

    private let service: ConvoyService

    init(service: ConvoyService) {
        self.service = service
    }

    func loadConvoys() async {
        isLoading = true
        errorMessage = nil

        do {
            convoys = try await service.listConvoys()
            if let selectedConvoy,
               let refreshed = convoys.first(where: { $0.id == selectedConvoy.id }) {
                self.selectedConvoy = refreshed
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func loadConvoyDetails(convoyId: UUID) async {
        isLoading = true
        errorMessage = nil

        do {
            async let convoyTask = service.convoyDetails(id: convoyId)
            async let membersTask = service.convoyMembers(id: convoyId)

            let detail = try await convoyTask
            selectedConvoy = detail.convoy
            membership = detail.membership
            summary = detail.summary

            members = try await membersTask

            do {
                invites = try await service.listInvites(convoyId: convoyId)
            } catch {
                invites = []
            }

            do {
                locations = try await service.convoyLocations(id: convoyId)
            } catch {
                locations = []
            }

            do {
                presence = try await service.convoyPresence(id: convoyId)
            } catch {
                presence = []
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func createConvoy(name: String, description: String?, relayRegion: String?) async {
        isSubmitting = true
        errorMessage = nil

        do {
            let convoy = try await service.createConvoy(name: name, description: description, relayRegion: relayRegion)
            infoMessage = "Convoy created."
            selectedConvoy = convoy
            await loadConvoys()
            await loadConvoyDetails(convoyId: convoy.id)
        } catch {
            errorMessage = error.localizedDescription
        }

        isSubmitting = false
    }

    func joinConvoy(convoyId: UUID, token: String?, code: String?) async {
        isSubmitting = true
        errorMessage = nil

        do {
            try await service.joinConvoy(id: convoyId, token: token, code: code)
            infoMessage = "Joined convoy."
            await loadConvoys()
            await loadConvoyDetails(convoyId: convoyId)
        } catch {
            errorMessage = error.localizedDescription
        }

        isSubmitting = false
    }

    func leaveConvoy(convoyId: UUID) async {
        isSubmitting = true
        errorMessage = nil

        do {
            let leaveResult = try await service.leaveConvoy(id: convoyId)
            if leaveResult.convoyEnded {
                infoMessage = "Convoy ended after leaving."
                selectedConvoy = nil
                membership = nil
                summary = nil
                members = []
                invites = []
                locations = []
                presence = []
            } else if leaveResult.newOwnerUserId != nil {
                infoMessage = "Ownership transferred to another member."
            } else {
                infoMessage = "Left convoy."
                selectedConvoy = nil
                membership = nil
                summary = nil
                members = []
                invites = []
                locations = []
                presence = []
            }
            await loadConvoys()
        } catch {
            errorMessage = error.localizedDescription
        }

        isSubmitting = false
    }

    func endConvoy(convoyId: UUID) async {
        isSubmitting = true
        errorMessage = nil

        do {
            try await service.endConvoy(id: convoyId)
            infoMessage = "Convoy ended."
            selectedConvoy = nil
            membership = nil
            summary = nil
            members = []
            invites = []
            locations = []
            presence = []
            await loadConvoys()
        } catch {
            errorMessage = error.localizedDescription
        }

        isSubmitting = false
    }

    func createInvite(convoyId: UUID, type: InviteType, targetUserId: UUID?, maxUses: Int?, expiresAt: Date?) async {
        isSubmitting = true
        errorMessage = nil

        do {
            let expiresInSeconds = expiresAt.map {
                max(1, Int($0.timeIntervalSinceNow.rounded(.up)))
            }
            let invite = try await service.createInvite(
                convoyId: convoyId,
                request: CreateInviteRequest(type: type, targetUserId: targetUserId, maxUses: maxUses, expiresInSeconds: expiresInSeconds)
            )
            if invite.type == .link, let token = invite.token {
                var components = URLComponents()
                components.scheme = "convoy"
                components.host = "join"
                components.queryItems = [URLQueryItem(name: "token", value: token)]
                lastInviteSecret = components.string ?? token
                infoMessage = "Link invite created. Share the deep link now."
            } else {
                lastInviteSecret = invite.code ?? invite.token
                infoMessage = invite.type == .code ? "Code invite created. Save the code now." : "Invite created. Save the secret now."
            }
            invites.insert(invite, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }

        isSubmitting = false
    }

    func revokeInvite(convoyId: UUID, inviteId: UUID) async {
        isSubmitting = true
        errorMessage = nil

        do {
            try await service.revokeInvite(convoyId: convoyId, inviteId: inviteId)
            invites.removeAll { $0.id == inviteId }
            infoMessage = "Invite revoked."
        } catch {
            errorMessage = error.localizedDescription
        }

        isSubmitting = false
    }

    func acceptInvite(token: String?, code: String?) async {
        isSubmitting = true
        errorMessage = nil

        do {
            let result = try await service.acceptInvite(
                token: token,
                code: code?.uppercased()
            )
            selectedConvoy = result.convoy
            membership = result.membership
            navigationConvoyID = result.convoy.id
            infoMessage = "Invite accepted."
            await loadConvoys()
            await loadConvoyDetails(convoyId: result.convoy.id)
        } catch {
            if let clientError = error as? APIClientError,
               case .serverError(let status, let payload, _) = clientError {
                switch (status, payload?.error) {
                case (404, "invite_not_found"):
                    errorMessage = "That invite was not found. Check the link or code and try again."
                case (410, "invite_expired"):
                    errorMessage = "This invite has expired. Ask for a new one."
                case (409, "invite_exhausted"):
                    errorMessage = "This invite has already been used up."
                case (409, "invite_inactive"):
                    errorMessage = "This invite is no longer active."
                case (409, "convoy_ended"):
                    errorMessage = "This convoy has already ended."
                default:
                    errorMessage = error.localizedDescription
                }
            } else {
                errorMessage = error.localizedDescription
            }
        }

        isSubmitting = false
    }

    func consumeNavigationConvoyID() {
        navigationConvoyID = nil
    }

    func loadPresence(convoyId: UUID) async {
        do {
            presence = try await service.convoyPresence(id: convoyId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadLocations(convoyId: UUID) async {
        do {
            locations = try await service.convoyLocations(id: convoyId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateLocation(convoyId: UUID, latitude: Double, longitude: Double, speed: Double?) async {
        do {
            try await service.updateLocation(convoyId: convoyId, latitude: latitude, longitude: longitude, speed: speed)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updatePresence(convoyId: UUID, listening: Bool, muted: Bool, lastAudioReceived: Date?) async {
        do {
            try await service.updatePresence(convoyId: convoyId, listening: listening, muted: muted, lastAudioReceived: lastAudioReceived)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateMemberRole(convoyId: UUID, userId: UUID, role: MemberRole) async {
        isSubmitting = true
        errorMessage = nil

        do {
            _ = try await service.updateMemberRole(convoyId: convoyId, userId: userId, role: role)
            if let index = members.firstIndex(where: { $0.userId == userId }) {
                var updated = members[index]
                updated = ConvoyMember(
                    userId: updated.userId,
                    username: updated.username,
                    displayName: updated.displayName,
                    role: role,
                    status: updated.status,
                    joinedAt: updated.joinedAt,
                    leftAt: updated.leftAt
                )
                members[index] = updated
            }
            infoMessage = "Member role updated."
        } catch {
            errorMessage = error.localizedDescription
        }

        isSubmitting = false
    }

    func removeMember(convoyId: UUID, userId: UUID) async {
        isSubmitting = true
        errorMessage = nil

        do {
            try await service.removeMember(convoyId: convoyId, userId: userId)
            members.removeAll { $0.userId == userId }
            if let current = summary {
                self.summary = ConvoySummary(memberCount: max(0, current.memberCount - 1))
            }
            infoMessage = "Member removed."
        } catch {
            errorMessage = error.localizedDescription
        }

        isSubmitting = false
    }
}

private extension ISO8601DateFormatter {
    static let standard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let fractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

extension ConvoyStore {
    static func live() -> ConvoyStore {
        let apiClient = APIClient(
            accessTokenProvider: {
                let session = try await supabase.auth.session
                return session.accessToken
            },
            refreshAuthSession: {
                let refreshedSession = try await supabase.auth.refreshSession()
                return refreshedSession.accessToken
            }
        )
        return ConvoyStore(service: ConvoyService(apiClient: apiClient))
    }
}
