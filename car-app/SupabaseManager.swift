//
//  SupabaseManager.swift
//  car-app
//

import Foundation
import UIKit
import Supabase

let supabase = SupabaseClient(
    supabaseURL: URL(string: "https://fluritbenwgztxhaukhy.supabase.co")!,
    supabaseKey: "sb_publishable_7BMmdzf3IZiXk51rGYPUHA_OZ049Pe0",
    options: SupabaseClientOptions(
        auth: .init(
            emitLocalSessionAsInitialSession: true
        )
    )
)

private struct UserProfileRecord: Encodable {
    let id: UUID
    let username: String
    let preferredName: String
    let carModel: String?
    let avatarURL: String

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case preferredName = "preferred_name"
        case carModel = "car_model"
        case avatarURL = "avatar_url"
    }
}

struct UserProfileRow: Decodable, Identifiable {
    let id: UUID
    let username: String?
    let preferredName: String?
    let carModel: String?
    let avatarURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case preferredName = "preferred_name"
        case carModel = "car_model"
        case avatarURL = "avatar_url"
    }

    var isComplete: Bool {
        guard let username, !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let preferredName, !preferredName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let avatarURL, !avatarURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        return true
    }
}

struct FriendRequestRow: Decodable, Identifiable {
    let id: Int64
    let sender: UUID?
    let receiver: UUID?
    let status: String
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case sender
        case receiver
        case status
        case createdAt = "created_at"
    }
}

struct PendingFriendRequest: Identifiable {
    let request: FriendRequestRow
    let requester: UserProfileRow?

    var id: Int64 { request.id }
}

private struct FriendRequestInsertRecord: Encodable {
    let sender: UUID
    let receiver: UUID
    let status: String

    enum CodingKeys: String, CodingKey {
        case sender
        case receiver
        case status
    }
}

private struct FriendshipRecord: Encodable {
    let userID: UUID
    let friendID: UUID

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case friendID = "friend_id"
    }
}

enum UserProfileStorageError: LocalizedError {
    case invalidAvatarData
    case missingExistingAvatar

    var errorDescription: String? {
        switch self {
        case .invalidAvatarData:
            return "The selected profile photo could not be prepared for upload."
        case .missingExistingAvatar:
            return "A profile photo is required before saving your profile."
        }
    }
}

func fetchCurrentUserProfile() async throws -> UserProfileRow? {
    let user = try await supabase.auth.user()
    return try await fetchUserProfile(for: user.id)
}

func fetchUserProfile(for userID: UUID) async throws -> UserProfileRow? {
    let profiles: [UserProfileRow] = try await supabase
        .from("users")
        .select("id, username, preferred_name, car_model, avatar_url")
        .eq("id", value: userID)
        .limit(1)
        .execute()
        .value

    return profiles.first
}

func resolveAvatarURL(from avatarReference: String?) async -> URL? {
    guard let avatarReference,
          let avatarPath = avatarStoragePath(from: avatarReference) else {
        return nil
    }

    return try? await supabase.storage
        .from("avatars")
        .createSignedURL(path: avatarPath, expiresIn: 3600)
}

func updateUserProfile(
    username: String,
    preferredName: String,
    carModel: String?,
    newAvatarData: Data?
) async throws -> UserProfileRow {
    let user = try await supabase.auth.user()
    let existingProfile = try await fetchUserProfile(for: user.id)
    let avatarPath = "\(user.id.uuidString)/avatar.jpg"

    let avatarReference: String
    if let newAvatarData {
        guard let image = UIImage(data: newAvatarData),
              let jpegData = image.jpegData(compressionQuality: 0.85) else {
            throw UserProfileStorageError.invalidAvatarData
        }

        try await supabase.storage
            .from("avatars")
            .upload(
                avatarPath,
                data: jpegData,
                options: FileOptions(
                    cacheControl: "3600",
                    contentType: "image/jpeg",
                    upsert: true
                )
            )

        avatarReference = avatarPath
    } else if let existingAvatarURL = existingProfile?.avatarURL,
              !existingAvatarURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        avatarReference = existingAvatarURL
    } else {
        throw UserProfileStorageError.missingExistingAvatar
    }

    let record = UserProfileRecord(
        id: user.id,
        username: username,
        preferredName: preferredName,
        carModel: carModel,
        avatarURL: avatarReference
    )

    try await supabase
        .from("users")
        .upsert(record, onConflict: "id")
        .execute()

    guard let updatedProfile = try await fetchUserProfile(for: user.id) else {
        throw UserProfileStorageError.missingExistingAvatar
    }

    return updatedProfile
}

func createUserProfile(from payload: OnboardingProfilePayload) async throws {
    let user = try await supabase.auth.user()
    let avatarData = try payload.avatarUploadData()
    let avatarPath = "\(user.id.uuidString)/avatar.jpg"

    try await supabase.storage
        .from("avatars")
        .upload(
            avatarPath,
            data: avatarData,
            options: FileOptions(
                cacheControl: "3600",
                contentType: "image/jpeg",
                upsert: true
            )
        )

    let record = UserProfileRecord(
        id: user.id,
        username: payload.username,
        preferredName: payload.informalName,
        carModel: payload.carType,
        avatarURL: avatarPath
    )

    do {
        try await supabase
            .from("users")
            .upsert(record, onConflict: "id")
            .execute()
    } catch {
        _ = try? await supabase.storage
            .from("avatars")
            .remove(paths: [avatarPath])
        throw error
    }
}

func fetchPendingFriendRequests() async throws -> [PendingFriendRequest] {
    let user = try await supabase.auth.user()
    let requests: [FriendRequestRow] = try await supabase
        .from("friend_requests")
        .select("id, sender, receiver, status, created_at")
        .eq("receiver", value: user.id)
        .eq("status", value: "pending")
        .order("created_at", ascending: false)
        .execute()
        .value

    var pendingRequests: [PendingFriendRequest] = []
    for request in requests {
        let requester: UserProfileRow?
        if let sender = request.sender {
            requester = try await fetchUserProfile(for: sender)
        } else {
            requester = nil
        }
        pendingRequests.append(PendingFriendRequest(request: request, requester: requester))
    }

    return pendingRequests
}

func searchUsers(matching query: String) async throws -> [UserProfileRow] {
    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedQuery.isEmpty else { return [] }

    let currentUser = try await supabase.auth.user()
    return try await supabase
        .from("users")
        .select("id, username, preferred_name, car_model, avatar_url")
        .ilike("username", pattern: "%\(trimmedQuery)%")
        .neq("id", value: currentUser.id)
        .order("username", ascending: true)
        .limit(10)
        .execute()
        .value
}

func sendFriendRequest(to recipientUserID: UUID) async throws {
    let currentUser = try await supabase.auth.user()
    let request = FriendRequestInsertRecord(
        sender: currentUser.id,
        receiver: recipientUserID,
        status: "pending"
    )

    try await supabase
        .from("friend_requests")
        .insert(request)
        .execute()
}

func acceptFriendRequest(id: Int64) async throws {
    let currentUser = try await supabase.auth.user()
    let requests: [FriendRequestRow] = try await supabase
        .from("friend_requests")
        .select("id, sender, receiver, status, created_at")
        .eq("id", value: String(id))
        .eq("receiver", value: currentUser.id)
        .limit(1)
        .execute()
        .value

    guard let request = requests.first,
          let sender = request.sender else {
        return
    }

    try await supabase
        .from("friend_requests")
        .update(["status": "accepted"])
        .eq("id", value: String(id))
        .eq("receiver", value: currentUser.id)
        .execute()

    let friendshipRows = [
        FriendshipRecord(userID: currentUser.id, friendID: sender),
        FriendshipRecord(userID: sender, friendID: currentUser.id)
    ]

    try await supabase
        .from("friendships")
        .insert(friendshipRows)
        .execute()
}

func declineFriendRequest(id: Int64) async throws {
    let currentUser = try await supabase.auth.user()
    try await supabase
        .from("friend_requests")
        .delete()
        .eq("id", value: String(id))
        .eq("receiver", value: currentUser.id)
        .execute()
}

private func avatarStoragePath(from avatarReference: String) -> String? {
    let trimmedReference = avatarReference.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedReference.isEmpty else { return nil }

    if !trimmedReference.contains("://") {
        return trimmedReference
    }

    guard let url = URL(string: trimmedReference) else {
        return nil
    }

    let marker = "/avatars/"
    let absoluteString = url.absoluteString
    if let range = absoluteString.range(of: marker) {
        return String(absoluteString[range.upperBound...])
            .components(separatedBy: "?")
            .first
    }

    return url.pathComponents
        .drop { $0 != "avatars" }
        .dropFirst()
        .joined(separator: "/")
        .nilIfEmpty
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
