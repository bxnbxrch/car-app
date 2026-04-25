//
//  ContentView.swift
//  car-app
//
//  Created by Ben Birch on 25/04/2026.
//

import SwiftUI
import SwiftData
import PhotosUI
import Supabase

struct ContentView: View {
    @State private var profile: UserProfileRow?
    @State private var username = ""
    @State private var preferredName = ""
    @State private var carModel = ""
    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var selectedAvatarData: Data?
    @State private var pendingFriendRequests: [PendingFriendRequest] = []
    @State private var searchQuery = ""
    @State private var searchResults: [UserProfileRow] = []
    @State private var isLoadingDashboard = true
    @State private var isSavingProfile = false
    @State private var isSearchingUsers = false
    @State private var activeFriendActionID: String?
    @State private var dashboardError: String?
    @State private var profileStatusMessage: String?
    @State private var friendStatusMessage: String?
    @State private var showSettingsSheet = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.appBackground
                    .ignoresSafeArea()

                if isLoadingDashboard {
                    ProgressView()
                        .tint(AppTheme.brandAccent)
                        .scaleEffect(1.2)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            headerCard
                            friendRequestsCard
                            profileCard
                            addFriendsCard
                        }
                        .padding(20)
                    }
                }
            }
        }
        .task {
            await loadDashboard()
        }
        .refreshable {
            await loadDashboard()
        }
        .onChange(of: selectedAvatarItem) { _, newItem in
            guard let newItem else { return }
            loadSelectedAvatar(newItem)
        }
        .sheet(isPresented: $showSettingsSheet) {
            settingsSheet
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your convoy dashboard")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text("Manage your profile, review friend requests, and invite new people into your network.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Spacer(minLength: 16)

                Menu {
                    Button("Settings") {
                        showSettingsSheet = true
                    }

                    Button("Refresh") {
                        Task {
                            await loadDashboard()
                        }
                    }

                    Button("Sign Out", role: .destructive) {
                        Task {
                            try? await supabase.auth.signOut()
                        }
                    }
                } label: {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(AppTheme.textPrimary)
                }
            }

            if let dashboardError {
                statusBanner(text: dashboardError, color: .red, isError: true)
            }

            if let friendStatusMessage {
                statusBanner(text: friendStatusMessage, color: AppTheme.brandAccent)
            }
        }
        .padding(20)
        .background(AppTheme.surfaceCard)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius)
                .stroke(AppTheme.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))
    }

    private var friendRequestsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Friend requests")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer()

                Text("\(pendingFriendRequests.count)")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppTheme.surfaceSecondary)
                    .clipShape(Capsule())
            }

            if pendingFriendRequests.isEmpty {
                Text("No pending requests right now.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
            } else {
                ForEach(pendingFriendRequests) { request in
                    HStack(spacing: 14) {
                        profileAvatar(urlString: request.requester?.avatarURL, size: 52)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(request.requester?.preferredName ?? "Unknown user")
                                .font(.headline)
                                .foregroundStyle(AppTheme.textPrimary)

                            Text("@\(request.requester?.username ?? "unknown")")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.textSecondary)
                        }

                        Spacer()

                        if activeFriendActionID == friendRequestActionID(for: request.id) {
                            ProgressView()
                                .tint(AppTheme.brandAccent)
                        } else {
                            Button("Accept") {
                                Task {
                                    await respondToFriendRequest(id: request.id, accept: true)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(AppTheme.brandAccent)

                            Button("Decline") {
                                Task {
                                    await respondToFriendRequest(id: request.id, accept: false)
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(14)
                    .background(AppTheme.surfaceSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                }
            }
        }
        .padding(20)
        .background(AppTheme.surfaceCard)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius)
                .stroke(AppTheme.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))
    }

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Profile")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer()

                if isSavingProfile {
                    ProgressView()
                        .tint(AppTheme.brandAccent)
                } else {
                    Button("Save changes") {
                        Task {
                            await saveProfile()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.brandAccent)
                    .disabled(!canSaveProfile)
                }
            }

            if let profileStatusMessage {
                statusBanner(text: profileStatusMessage, color: AppTheme.brandAccent)
            }

            HStack(alignment: .top, spacing: 16) {
                PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
                    ZStack(alignment: .bottomTrailing) {
                        editableProfileAvatar

                        Image(systemName: "camera.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(AppTheme.brandAccent)
                            .clipShape(Circle())
                            .offset(x: 4, y: 4)
                    }
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 14) {
                    profileField(title: "Username", text: $username, prompt: "username")
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    profileField(title: "Preferred name", text: $preferredName, prompt: "Preferred name")
                    profileField(title: "Car model", text: $carModel, prompt: "Car model")
                }
            }

            if let profile {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Current backend data")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)

                    Text("ID: \(profile.id.uuidString)")
                        .font(.footnote.monospaced())
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
        }
        .padding(20)
        .background(AppTheme.surfaceCard)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius)
                .stroke(AppTheme.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))
    }

    private var addFriendsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add friends")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)

            HStack(spacing: 12) {
                TextField("Search by username", text: $searchQuery)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .background(AppTheme.surfaceSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                Button("Search") {
                    Task {
                        await runUserSearch()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.brandAccent)
                .disabled(searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearchingUsers)
            }

            if isSearchingUsers {
                ProgressView()
                    .tint(AppTheme.brandAccent)
            } else if searchResults.isEmpty {
                Text("Search for another username to send a friend request.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
            } else {
                ForEach(searchResults) { result in
                    HStack(spacing: 14) {
                        profileAvatar(urlString: result.avatarURL, size: 52)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.preferredName ?? "Unnamed user")
                                .font(.headline)
                                .foregroundStyle(AppTheme.textPrimary)

                            Text("@\(result.username ?? "unknown")")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.textSecondary)
                        }

                        Spacer()

                        if activeFriendActionID == userActionID(for: result.id) {
                            ProgressView()
                                .tint(AppTheme.brandAccent)
                        } else {
                            Button("Send request") {
                                Task {
                                    await sendRequest(to: result.id)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(AppTheme.brandAccent)
                        }
                    }
                    .padding(14)
                    .background(AppTheme.surfaceSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                }
            }
        }
        .padding(20)
        .background(AppTheme.surfaceCard)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius)
                .stroke(AppTheme.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))
    }

    private var editableProfileAvatar: some View {
        Group {
            if let selectedAvatarData,
               let image = UIImage(data: selectedAvatarData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                profileAvatar(urlString: profile?.avatarURL, size: 96)
            }
        }
        .frame(width: 96, height: 96)
        .background(AppTheme.surfaceSecondary)
        .clipShape(Circle())
    }

    private var canSaveProfile: Bool {
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !preferredName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (selectedAvatarData != nil || !(profile?.avatarURL?.isEmpty ?? true))
    }

    private var settingsSheet: some View {
        NavigationStack {
            List {
                Section("Account") {
                    if let profile {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(profile.preferredName ?? "Unknown user")
                                .font(.headline)
                            Text("@\(profile.username ?? "unknown")")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button("Sign Out", role: .destructive) {
                        Task {
                            try? await supabase.auth.signOut()
                        }
                    }
                }

                Section("Settings") {
                    Text("More settings can live here as the dashboard grows.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Profile Menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showSettingsSheet = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func profileField(title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)

            TextField(prompt, text: text)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(AppTheme.surfaceSecondary)
                .foregroundStyle(AppTheme.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private func profileAvatar(urlString: String?, size: CGFloat) -> some View {
        AvatarImageView(avatarReference: urlString, size: size)
        .frame(width: size, height: size)
        .background(AppTheme.surfaceSecondary)
        .clipShape(Circle())
    }

    private var avatarPlaceholder: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .scaledToFit()
            .padding(12)
            .foregroundStyle(AppTheme.textSecondary)
    }

    private func statusBanner(text: String, color: Color, isError: Bool = false) -> some View {
        Text(text)
            .font(.footnote.weight(.medium))
            .foregroundStyle(isError ? Color.red : AppTheme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @MainActor
    private func populateProfileFields(from profile: UserProfileRow?) {
        self.profile = profile
        username = profile?.username ?? ""
        preferredName = profile?.preferredName ?? ""
        carModel = profile?.carModel ?? ""
        selectedAvatarData = nil
    }

    private func loadDashboard() async {
        await MainActor.run {
            isLoadingDashboard = true
            dashboardError = nil
        }

        do {
            async let profileTask = fetchCurrentUserProfile()
            async let requestsTask = fetchPendingFriendRequests()

            let loadedProfile = try await profileTask
            let loadedRequests = try await requestsTask

            await MainActor.run {
                populateProfileFields(from: loadedProfile)
                pendingFriendRequests = loadedRequests
                isLoadingDashboard = false
            }
        } catch {
            await MainActor.run {
                dashboardError = error.localizedDescription
                isLoadingDashboard = false
            }
        }
    }

    private func loadSelectedAvatar(_ item: PhotosPickerItem) {
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                await MainActor.run {
                    selectedAvatarData = data
                }
            }
        }
    }

    private func saveProfile() async {
        await MainActor.run {
            isSavingProfile = true
            profileStatusMessage = nil
        }

        do {
            let updatedProfile = try await updateUserProfile(
                username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                preferredName: preferredName.trimmingCharacters(in: .whitespacesAndNewlines),
                carModel: carModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil
                    : carModel.trimmingCharacters(in: .whitespacesAndNewlines),
                newAvatarData: selectedAvatarData
            )

            await MainActor.run {
                populateProfileFields(from: updatedProfile)
                profileStatusMessage = "Profile updated."
                isSavingProfile = false
            }
        } catch {
            await MainActor.run {
                profileStatusMessage = error.localizedDescription
                isSavingProfile = false
            }
        }
    }

    private func runUserSearch() async {
        await MainActor.run {
            isSearchingUsers = true
            friendStatusMessage = nil
        }

        do {
            let results = try await searchUsers(matching: searchQuery)
            await MainActor.run {
                searchResults = results
                isSearchingUsers = false
            }
        } catch {
            await MainActor.run {
                friendStatusMessage = error.localizedDescription
                isSearchingUsers = false
            }
        }
    }

    private func sendRequest(to userID: UUID) async {
        await MainActor.run {
            activeFriendActionID = userActionID(for: userID)
            friendStatusMessage = nil
        }

        do {
            try await sendFriendRequest(to: userID)
            await MainActor.run {
                friendStatusMessage = "Friend request sent."
                searchResults.removeAll { $0.id == userID }
                activeFriendActionID = nil
            }
        } catch {
            await MainActor.run {
                friendStatusMessage = error.localizedDescription
                activeFriendActionID = nil
            }
        }
    }

    private func respondToFriendRequest(id: Int64, accept: Bool) async {
        await MainActor.run {
            activeFriendActionID = friendRequestActionID(for: id)
            friendStatusMessage = nil
        }

        do {
            if accept {
                try await acceptFriendRequest(id: id)
            } else {
                try await declineFriendRequest(id: id)
            }

            let refreshedRequests = try await fetchPendingFriendRequests()
            await MainActor.run {
                pendingFriendRequests = refreshedRequests
                friendStatusMessage = accept ? "Friend request accepted." : "Friend request declined."
                activeFriendActionID = nil
            }
        } catch {
            await MainActor.run {
                friendStatusMessage = error.localizedDescription
                activeFriendActionID = nil
            }
        }
    }

    private func userActionID(for userID: UUID) -> String {
        "user-\(userID.uuidString)"
    }

    private func friendRequestActionID(for requestID: Int64) -> String {
        "request-\(requestID)"
    }
}

private struct AvatarImageView: View {
    let avatarReference: String?
    let size: CGFloat

    @State private var resolvedURL: URL?

    var body: some View {
        Group {
            if let resolvedURL {
                AsyncImage(url: resolvedURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .empty:
                        ProgressView()
                            .tint(AppTheme.brandAccent)
                    default:
                        avatarPlaceholder
                    }
                }
            } else {
                avatarPlaceholder
            }
        }
        .task(id: avatarReference) {
            resolvedURL = await resolveAvatarURL(from: avatarReference)
        }
        .frame(width: size, height: size)
    }

    private var avatarPlaceholder: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .scaledToFit()
            .padding(12)
            .foregroundStyle(AppTheme.textSecondary)
    }
}

struct OnboardingProfilePayload: Codable {
    let username: String
    let informalName: String
    let avatarBase64: String
    let carType: String?

    var asDictionary: [String: String] {
        var data: [String: String] = [
            "username": username,
            "informal_name": informalName,
            "avatar_base64": avatarBase64
        ]

        if let carType, !carType.isEmpty {
            data["car_type"] = carType
        }

        return data
    }

    var jsonString: String? {
        guard let encoded = try? JSONEncoder().encode(self) else { return nil }
        return String(data: encoded, encoding: .utf8)
    }

    func avatarUploadData() throws -> Data {
        guard let rawData = Data(base64Encoded: avatarBase64),
              let image = UIImage(data: rawData),
              let jpegData = image.jpegData(compressionQuality: 0.85) else {
            throw UserProfileStorageError.invalidAvatarData
        }

        return jpegData
    }
}

struct PostLoginOnboardingView: View {
    enum Step: Int, CaseIterable {
        case username
        case informalName
        case profilePhoto
        case carType
    }

    let onComplete: (OnboardingProfilePayload) async throws -> Void

    @State private var step: Step = .username
    @State private var username = ""
    @State private var informalName = ""
    @State private var carType = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var avatarData: Data?
    @State private var avatarUIImage: UIImage?
    @State private var isLoadingPhoto = false
    @State private var isSubmitting = false
    @State private var submissionError: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                header

                Group {
                    switch step {
                    case .username:
                        usernameStep
                    case .informalName:
                        informalNameStep
                    case .profilePhoto:
                        profilePhotoStep
                    case .carType:
                        carTypeStep
                    }
                }

                Spacer()

                navigationButtons
            }
            .padding(24)
            .navigationBarBackButtonHidden(true)
            .interactiveDismissDisabled(isSubmitting)
            .onChange(of: selectedPhoto) { _, newItem in
                guard let newItem else { return }
                loadSelectedPhoto(newItem)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Setup your profile")
                .font(.title)
                .fontWeight(.bold)

            Text("Step \(step.rawValue + 1) of \(Step.allCases.count)")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)

            ProgressView(value: Double(step.rawValue + 1), total: Double(Step.allCases.count))
                .tint(AppTheme.brandAccent)
        }
    }

    private var usernameStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pick a unique username")
                .font(.title2)
                .fontWeight(.semibold)

            Text("This should be unique. You can use lowercase letters, numbers, and underscores.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)

            TextField("e.g. ben_drives", text: $username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding()
                .background(AppTheme.surfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            if !username.isEmpty && !isValidUsername {
                Text("Use 3-20 characters: lowercase letters, numbers, underscores.")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var informalNameStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What should we call you?")
                .font(.title2)
                .fontWeight(.semibold)

            Text("This is your informal name shown around the app.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)

            TextField("e.g. Ben", text: $informalName)
                .padding()
                .background(AppTheme.surfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var profilePhotoStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add a profile photo")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Choose the photo you'd like to use for your profile.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)

            HStack(spacing: 16) {
                Group {
                    if let avatarUIImage {
                        Image(uiImage: avatarUIImage)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .padding(22)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 96, height: 96)
                .background(AppTheme.surfaceSecondary)
                .clipShape(Circle())

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Text(isLoadingPhoto ? "Loading photo..." : "Choose Photo")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppTheme.brandAccent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isLoadingPhoto)
            }

            if avatarData == nil {
                Text("A profile photo is required.")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var carTypeStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What do you drive? (optional)")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Add your car type now, or skip and do it later.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)

            TextField("e.g. Tesla Model 3", text: $carType)
                .padding()
                .background(AppTheme.surfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var navigationButtons: some View {
        VStack(spacing: 10) {
            if let submissionError {
                Text(submissionError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.leading)
            }

            Button(action: advance) {
                Group {
                    if isSubmitting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(step == .carType ? "Finish" : "Continue")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(canContinue ? AppTheme.brandAccent : AppTheme.buttonDisabled)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!canContinue || isSubmitting)

            if step.rawValue > 0 {
                Button("Back") {
                    step = Step(rawValue: step.rawValue - 1) ?? .username
                }
                .frame(maxWidth: .infinity)
                .disabled(isSubmitting)
            }
        }
    }

    private var isValidUsername: Bool {
        let candidate = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let regex = try? NSRegularExpression(pattern: "^[a-z0-9_]{3,20}$")
        let range = NSRange(location: 0, length: candidate.utf16.count)
        return regex?.firstMatch(in: candidate, options: [], range: range) != nil
    }

    private var canContinue: Bool {
        switch step {
        case .username:
            return isValidUsername
        case .informalName:
            return !informalName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .profilePhoto:
            return avatarData != nil && !isLoadingPhoto
        case .carType:
            return true
        }
    }

    private func loadSelectedPhoto(_ item: PhotosPickerItem) {
        isLoadingPhoto = true
        Task {
            defer {
                Task { @MainActor in
                    isLoadingPhoto = false
                }
            }

            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                await MainActor.run {
                    avatarData = data
                    avatarUIImage = image
                }
            }
        }
    }

    private func advance() {
        if step == .carType {
            guard let avatarData else { return }
            submissionError = nil
            let payload = OnboardingProfilePayload(
                username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                informalName: informalName.trimmingCharacters(in: .whitespacesAndNewlines),
                avatarBase64: avatarData.base64EncodedString(),
                carType: carType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil
                    : carType.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            isSubmitting = true
            Task {
                do {
                    try await onComplete(payload)
                } catch {
                    await MainActor.run {
                        submissionError = error.localizedDescription
                        isSubmitting = false
                    }
                }
            }
            return
        }

        submissionError = nil
        step = Step(rawValue: step.rawValue + 1) ?? .carType
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
