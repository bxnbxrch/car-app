import Foundation

enum ConvoyStatus: String, Codable {
    case active
    case ended
}

enum MemberRole: String, Codable {
    case owner
    case admin
    case member
}

enum MemberStatus: String, Codable {
    case active
    case left
    case removed
}

enum InviteType: String, Codable {
    case link
    case code
    case directUser = "direct_user"
}

enum InviteStatus: String, Codable {
    case pending
    case accepted
    case declined
    case revoked
    case expired
}

struct Convoy: Codable, Identifiable {
    let id: UUID
    let name: String
    let description: String?
    let relayRegion: String?
    let status: ConvoyStatus
    let createdAt: Date
    let updatedAt: Date?
    let endedAt: Date?
    let memberCount: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case relayRegion = "relay_region"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case endedAt = "ended_at"
        case memberCount = "member_count"
    }
}

struct ConvoyMembership: Codable {
    let userId: UUID
    let role: MemberRole
    let status: MemberStatus
    let joinedAt: Date?
    let leftAt: Date?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case role
        case status
        case joinedAt = "joined_at"
        case leftAt = "left_at"
    }
}

struct ConvoySummary: Codable {
    let memberCount: Int

    enum CodingKeys: String, CodingKey {
        case memberCount = "memberCount"
    }
}

struct ConvoyDetailPayload: Codable {
    let convoy: Convoy
    let membership: ConvoyMembership
    let summary: ConvoySummary?
}

struct ConvoyMembersPayload: Codable {
    let members: [ConvoyMember]
}

struct ConvoyInvitesPayload: Codable {
    let invites: [ConvoyInvite]
}

struct InviteAcceptanceResult: Codable {
    let convoy: Convoy
    let membership: ConvoyMembership
}

struct ConvoyMember: Codable, Identifiable {
    var id: UUID { userId }
    let userId: UUID
    let username: String?
    let displayName: String?
    let role: MemberRole
    let status: MemberStatus
    let joinedAt: Date?
    let leftAt: Date?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
        case displayName = "display_name"
        case role
        case status
        case joinedAt = "joined_at"
        case leftAt = "left_at"
    }
}

struct ConvoyLocation: Codable, Identifiable, Equatable {
    var id: UUID { userId }
    let userId: UUID
    let username: String?
    let displayName: String?
    let latitude: Double
    let longitude: Double
    let speed: Double?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
        case displayName = "display_name"
        case latitude
        case longitude
        case speed
        case updatedAt = "updated_at"
    }
}

struct ConvoyLocationsPayload: Codable {
    let locations: [ConvoyLocation]
}

struct ConvoyPresence: Codable, Identifiable {
    var id: UUID { userId }
    let userId: UUID
    let username: String?
    let displayName: String?
    let listening: Bool
    let muted: Bool
    let lastAudioReceived: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
        case displayName = "display_name"
        case listening
        case muted
        case lastAudioReceived = "last_audio_received"
        case updatedAt = "updated_at"
    }
}

struct ConvoyPresencePayload: Codable {
    let presence: [ConvoyPresence]
}

struct ConvoyInvite: Codable, Identifiable {
    let id: UUID
    let convoyId: UUID
    let createdByUserId: UUID
    let type: InviteType
    let targetUserId: UUID?
    let status: InviteStatus
    let maxUses: Int?
    let usesCount: Int
    let expiresAt: Date?
    let acceptedByUserId: UUID?
    let acceptedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let token: String?
    let code: String?

    // Backend sanitizeInvite() returns camelCase keys — no custom CodingKeys needed.
}

struct APIErrorPayload: Codable {
    let error: String
    let message: String?
    let details: [String: String]?
}

struct LeaveConvoyResult: Codable {
    let convoyEnded: Bool
    let newOwnerUserId: UUID?

    enum CodingKeys: String, CodingKey {
        case convoyEnded = "convoyEnded"
        case newOwnerUserId = "newOwnerUserId"
    }
}

struct ConnectRelayResponse: Codable {
    let relayHost: String
    let relayToken: String
    let relayPath: String?
    let relayId: String?

    enum CodingKeys: String, CodingKey {
        case relayHost = "relayHost"
        case relayToken = "relayToken"
        case relayPath = "relayPath"
        case relayId = "relayId"
    }
}
