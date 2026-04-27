import SwiftUI
import UIKit
import MapKit
import Supabase

struct ConvoysHomeView: View {
    @ObservedObject var convoyStore: ConvoyStore
    @ObservedObject var voiceStore: VoiceStore

    @State private var showCreateSheet = false
    @State private var navigationPath: [UUID] = []
    @State private var inviteToken = ""
    @State private var inviteCode = ""

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                AppTheme.appBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        joinInviteCard
                        convoysCard
                    }
                    .padding(20)
                }
            }
            .navigationDestination(for: UUID.self) { convoyID in
                ConvoyDetailView(convoyId: convoyID, convoyStore: convoyStore, voiceStore: voiceStore)
            }
            .navigationTitle("Convoys")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        print("[CONVOY][UI] Show create convoy sheet")
                        showCreateSheet = true
                    } label: {
                        Label("Create", systemImage: "plus")
                    }
                }
            }
            .task {
                await convoyStore.loadConvoys()
            }
            .refreshable {
                await convoyStore.loadConvoys()
            }
            .sheet(isPresented: $showCreateSheet) {
                ConvoyCreateSheet(convoyStore: convoyStore)
            }
            .onChange(of: convoyStore.navigationConvoyID) { _, convoyID in
                guard let convoyID else { return }
                if navigationPath.last != convoyID {
                    navigationPath.append(convoyID)
                }
                convoyStore.consumeNavigationConvoyID()
            }
            .safeAreaInset(edge: .bottom) {
                if let info = convoyStore.infoMessage {
                    MessageBanner(text: info, color: AppTheme.brandAccent)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                } else if let error = convoyStore.errorMessage {
                    MessageBanner(text: error, color: .red)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }
            }
        }
    }

    private var joinInviteCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Join by invite")
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer()

                Image(systemName: "link")
                    .foregroundStyle(AppTheme.brandAccent)
            }

            Text("Paste a convoy link or enter the invite token/code.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)

            VStack(spacing: 12) {
                TextField("Invite link or token", text: $inviteToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(AppTheme.surfaceField)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.fieldCornerRadius))

                TextField("Invite code", text: $inviteCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(AppTheme.surfaceField)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.fieldCornerRadius))
            }

            Button {
                let resolved = resolveInviteInputs()
                print("[CONVOY][UI] Accept Invite tapped token=\(resolved.token ?? "nil") code=\(resolved.code ?? "nil")")
                Task {
                    await convoyStore.acceptInvite(token: resolved.token, code: resolved.code)
                    inviteToken = ""
                    inviteCode = ""
                }
            } label: {
                HStack {
                    if convoyStore.isSubmitting {
                        ProgressView()
                    }
                    Text("Accept Invite")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.brandAccent)
            .disabled(convoyStore.isSubmitting || resolveInviteInputs().isEmpty)
        }
        .padding(20)
        .background(AppTheme.surfaceCard)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius)
                .stroke(AppTheme.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))
    }

    private var convoysCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Your convoys")
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer()

                if convoyStore.isLoading {
                    ProgressView()
                        .tint(AppTheme.brandAccent)
                }
            }

            if convoyStore.convoys.isEmpty {
                Text("You’re not in any active convoys yet.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
            } else {
                VStack(spacing: 12) {
                    ForEach(convoyStore.convoys) { convoy in
                        NavigationLink(value: convoy.id) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(convoy.name)
                                    .font(.headline)
                                    .foregroundStyle(AppTheme.textPrimary)

                                Text(convoy.description ?? "No description yet.")
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .lineLimit(2)

                                HStack(spacing: 8) {
                                    Text(convoy.status.rawValue.capitalized)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(convoy.status == .active ? AppTheme.brandAccent : .secondary)
                                    if let memberCount = convoy.memberCount {
                                        Text("\(memberCount) members")
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.textSecondary)
                                    }
                                    Text(convoy.createdAt.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.textSecondary)
                                }
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.surfaceSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                        }
                        .buttonStyle(.plain)
                    }
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

    private func resolveInviteInputs() -> (token: String?, code: String?, isEmpty: Bool) {
        let tokenInput = trimmed(inviteToken)
        let codeInput = trimmed(inviteCode)

        if let tokenInput,
           let url = URL(string: tokenInput),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItems = components.queryItems,
           !queryItems.isEmpty {
            let token = queryItems.first(where: { $0.name == "token" })?.value?.trimmedNil
            let code = queryItems.first(where: { $0.name == "code" })?.value?.trimmedNil
            return (token, code ?? codeInput, token == nil && (code ?? codeInput) == nil)
        }

        return (tokenInput, codeInput, tokenInput == nil && codeInput == nil)
    }

    private func trimmed(_ value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private struct ConvoyCreateSheet: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var convoyStore: ConvoyStore

    @State private var name = ""
    @State private var description = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Convoy") {
                    TextField("Name", text: $name)
                    TextField("Description (optional)", text: $description)
                }

                Section {
                    Button {
                        Task {
                            print("[CONVOY][UI] Create convoy tapped name=\(name)")
                            await convoyStore.createConvoy(
                                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                description: trimmed(description),
                                relayRegion: nil
                            )
                            if convoyStore.errorMessage == nil {
                                dismiss()
                            }
                        }
                    } label: {
                        HStack {
                            if convoyStore.isSubmitting {
                                ProgressView()
                            }
                            Text("Create convoy")
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || convoyStore.isSubmitting)
                }
            }
            .navigationTitle("New Convoy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func trimmed(_ value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private struct ConvoyDetailView: View {
    let convoyId: UUID

    @ObservedObject var convoyStore: ConvoyStore
    @ObservedObject var voiceStore: VoiceStore

    @State private var inviteType: InviteType = .code
    @StateObject private var locationManager = ConvoyLocationManager()
    @State private var shareLocation = true
    @State private var lastLocationSentAt: Date?
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 51.5072, longitude: -0.1276),
        span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
    )
    @State private var currentUserId: UUID?

    var body: some View {
        ZStack {
            AppTheme.appBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    convoyHeaderCard
                    mapCard
                    membersCard
                    invitesCard
                    voiceCard
                }
                .padding(20)
            }
        }
        .navigationTitle("Convoy")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await convoyStore.loadConvoyDetails(convoyId: convoyId)
            currentUserId = try? await supabase.auth.user().id
        }
        .refreshable {
            await convoyStore.loadConvoyDetails(convoyId: convoyId)
        }
        .task(id: convoyId) {
            while !Task.isCancelled {
                await convoyStore.loadPresence(convoyId: convoyId)
                await convoyStore.loadLocations(convoyId: convoyId)
                try? await Task.sleep(nanoseconds: 6_000_000_000)
            }
        }
        .onAppear {
            locationManager.requestAuthorization()
            if shareLocation {
                locationManager.startUpdates()
            }
        }
        .onDisappear {
            locationManager.stopUpdates()
        }
        .onChange(of: shareLocation) { _, isSharing in
            if isSharing {
                locationManager.startUpdates()
            } else {
                locationManager.stopUpdates()
            }
        }
        .onChange(of: locationManager.latestLocation) { _, newLocation in
            guard shareLocation, let newLocation else { return }
            let now = Date()
            if let lastLocationSentAt,
               now.timeIntervalSince(lastLocationSentAt) < 5 {
                return
            }
            lastLocationSentAt = now
            Task {
                await convoyStore.updateLocation(
                    convoyId: convoyId,
                    latitude: newLocation.coordinate.latitude,
                    longitude: newLocation.coordinate.longitude,
                    speed: newLocation.speed >= 0 ? newLocation.speed : nil
                )
            }
        }
        .onChange(of: convoyStore.locations) { _, locations in
            updateMapRegion(with: locations)
        }
        .safeAreaInset(edge: .bottom) {
            if let info = convoyStore.infoMessage {
                MessageBanner(text: info, color: AppTheme.brandAccent)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            } else if let error = convoyStore.errorMessage {
                MessageBanner(text: error, color: .red)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
    }

    private var membershipRole: MemberRole? {
        convoyStore.membership?.role
    }

    private var canManageInvites: Bool {
        membershipRole == .owner || membershipRole == .admin
    }

    private var canManageMembers: Bool {
        membershipRole == .owner || membershipRole == .admin
    }

    private var canEditRoles: Bool {
        membershipRole == .owner
    }

    private var convoyHeaderCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let convoy = convoyStore.selectedConvoy {
                Text(convoy.name)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(convoy.description ?? "No description yet.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)

                HStack(spacing: 10) {
                    statusPill(
                        text: convoy.status.rawValue.capitalized,
                        color: convoy.status == .active ? AppTheme.brandAccent : AppTheme.surfaceSecondary,
                        textColor: convoy.status == .active ? .white : AppTheme.textSecondary
                    )

                    if let memberCount = convoyStore.summary?.memberCount {
                        statusPill(text: "\(memberCount) members", color: AppTheme.surfaceSecondary, textColor: AppTheme.textSecondary)
                    }
                }
            } else if convoyStore.isLoading {
                ProgressView()
            }

            HStack(spacing: 12) {
                Button("Leave") {
                    Task {
                        await convoyStore.leaveConvoy(convoyId: convoyId)
                        voiceStore.disconnect()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(convoyStore.isSubmitting)

                if membershipRole == .owner || membershipRole == .admin {
                    Button("End") {
                        Task {
                            await convoyStore.endConvoy(convoyId: convoyId)
                            voiceStore.disconnect()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(convoyStore.isSubmitting)
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

    private var mapCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Live map")
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
            }

            Map(coordinateRegion: $mapRegion, showsUserLocation: shareLocation, annotationItems: convoyStore.locations) { location in
                MapAnnotation(coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)) {
                    mapAnnotationView(for: location)
                }
            }
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 18))

            Toggle("Share my location", isOn: $shareLocation)
                .toggleStyle(SwitchToggleStyle(tint: AppTheme.brandAccent))

            if convoyStore.locations.isEmpty {
                Text("No live locations yet. Share your location to get started.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(convoyStore.locations) { location in
                        HStack {
                            Text(location.displayName ?? location.username ?? location.userId.uuidString)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                            Spacer()
                            if let updatedAt = location.updatedAt {
                                Text(updatedAt, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                        }
                    }
                }
            }

            if let error = locationManager.errorMessage {
                MessageBanner(text: error, color: .red)
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

    private var membersCard: some View {
        let presenceLookup = Dictionary(uniqueKeysWithValues: convoyStore.presence.map { ($0.userId, $0) })

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Members")
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                if convoyStore.isLoading {
                    ProgressView()
                        .tint(AppTheme.brandAccent)
                }
            }

            if convoyStore.members.isEmpty {
                if convoyStore.isLoading {
                    ProgressView()
                        .tint(AppTheme.brandAccent)
                } else {
                    Text("No members visible.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            } else {
                VStack(spacing: 12) {
                    ForEach(convoyStore.members) { member in
                        HStack(spacing: 12) {
                            memberAvatarView(name: member.displayName ?? member.username ?? "Unknown")

                            VStack(alignment: .leading, spacing: 4) {
                                Text(member.displayName ?? member.username ?? member.userId.uuidString)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.textPrimary)

                                Text("@\(member.username ?? "unknown") • \(member.role.rawValue.capitalized)")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.textSecondary)
                            }

                            Spacer()

                            if let presence = presenceLookup[member.userId] {
                                presenceBadge(presence)
                            }

                            if canManageMembers,
                               let currentUserId,
                               member.userId != currentUserId {
                                Menu {
                                    if canEditRoles, member.role != .owner {
                                        Button("Make admin") {
                                            Task {
                                                await convoyStore.updateMemberRole(convoyId: convoyId, userId: member.userId, role: .admin)
                                            }
                                        }
                                        Button("Make member") {
                                            Task {
                                                await convoyStore.updateMemberRole(convoyId: convoyId, userId: member.userId, role: .member)
                                            }
                                        }
                                    }

                                    if canRemoveMember(member) {
                                        Button("Remove", role: .destructive) {
                                            Task {
                                                await convoyStore.removeMember(convoyId: convoyId, userId: member.userId)
                                            }
                                        }
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .foregroundStyle(AppTheme.textSecondary)
                                        .padding(8)
                                }
                            }
                        }
                        .padding(14)
                        .background(AppTheme.surfaceSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    }
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

    private var invitesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Invites")
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                if convoyStore.isSubmitting {
                    ProgressView()
                        .tint(AppTheme.brandAccent)
                }
            }

            if !canManageInvites {
                Text("Only owners and admins can manage invites.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
            } else {
                Picker("Type", selection: $inviteType) {
                    Text("Code").tag(InviteType.code)
                    Text("Link").tag(InviteType.link)
                }
                .pickerStyle(.segmented)

                Button("Create Invite") {
                    Task {
                        await convoyStore.createInvite(
                            convoyId: convoyId,
                            type: inviteType,
                            targetUserId: nil,
                            maxUses: 1,
                            expiresAt: Calendar.current.date(byAdding: .hour, value: 2, to: Date())
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.brandAccent)
                .disabled(convoyStore.isSubmitting)

                if let secret = convoyStore.lastInviteSecret {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Share this now:")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary)

                        Text(secret)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)

                        HStack(spacing: 12) {
                            Button("Copy") {
                                UIPasteboard.general.string = secret
                            }
                            .buttonStyle(.bordered)

                            if secret.contains("://"), let url = URL(string: secret) {
                                ShareLink("Share", item: url)
                                    .buttonStyle(.bordered)
                            } else {
                                ShareLink("Share", item: secret)
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                }

                if convoyStore.invites.isEmpty {
                    Text("No invites yet.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                } else {
                    VStack(spacing: 12) {
                        ForEach(convoyStore.invites) { invite in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(invite.type.rawValue.capitalized) • \(invite.status.rawValue.capitalized)")
                                    .font(.subheadline.weight(.semibold))

                                if let expiresAt = invite.expiresAt {
                                    Text("Expires \(expiresAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.footnote)
                                        .foregroundStyle(AppTheme.textSecondary)
                                }

                                if invite.status == .pending {
                                    Button("Revoke", role: .destructive) {
                                        Task {
                                            await convoyStore.revokeInvite(convoyId: convoyId, inviteId: invite.id)
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(convoyStore.isSubmitting)
                                }
                            }
                            .padding(14)
                            .background(AppTheme.surfaceSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                        }
                    }
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

    private var voiceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Voice")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            HStack {
                statusPill(text: label(for: voiceStore.connectionState), color: AppTheme.surfaceSecondary, textColor: AppTheme.textSecondary)
                statusPill(text: label(for: voiceStore.pttState), color: pttColor(voiceStore.pttState), textColor: pttTextColor(voiceStore.pttState))
            }

            if let speaker = voiceStore.currentSpeaker {
                Text("Speaker: \(speaker)")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            HStack(spacing: 12) {
                Button("Connect") {
                    print("[VOICE][UI] Connect tapped for convoyId=\(convoyId.uuidString)")
                    voiceStore.connect(convoyId: convoyId)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.brandAccent)
                .disabled(voiceStore.connectionState == .connected || voiceStore.connectionState == .connecting)

                Button("Disconnect") {
                    print("[VOICE][UI] Disconnect tapped for convoyId=\(convoyId.uuidString)")
                    voiceStore.disconnect()
                }
                .buttonStyle(.bordered)
                .disabled(voiceStore.connectionState == .disconnected)
            }

            PTTButton(
                isActive: voiceStore.pttState == .transmitting || voiceStore.pttState == .requestingFloor,
                isEnabled: voiceStore.connectionState == .connected,
                onPress: {
                    print("[VOICE][UI] PTT press (state=\(voiceStore.pttState))")
                    voiceStore.pressPTT()
                },
                onRelease: {
                    print("[VOICE][UI] PTT release (state=\(voiceStore.pttState))")
                    voiceStore.releasePTT()
                }
            )

            if let error = voiceStore.errorMessage {
                MessageBanner(text: error, color: .red)
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

    private func label(for state: VoiceConnectionState) -> String {
        switch state {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .reconnecting: return "Reconnecting"
        }
    }

    private func label(for state: PTTState) -> String {
        switch state {
        case .idle: return "Idle"
        case .requestingFloor: return "Requesting"
        case .transmitting: return "Transmitting"
        case .receiving: return "Receiving"
        case .blockedBusy: return "Busy"
        case .reconnecting: return "Reconnecting"
        }
    }

    private func pttColor(_ state: PTTState) -> Color {
        switch state {
        case .transmitting:
            return .green
        case .blockedBusy:
            return .orange
        case .reconnecting:
            return .yellow
        default:
            return .secondary
        }
    }

    private func pttTextColor(_ state: PTTState) -> Color {
        switch state {
        case .transmitting, .blockedBusy, .reconnecting:
            return .white
        default:
            return AppTheme.textSecondary
        }
    }

    private func statusPill(text: String, color: Color, textColor: Color = .white) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(textColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color)
            .clipShape(Capsule())
    }

    private func mapAnnotationView(for location: ConvoyLocation) -> some View {
        let initials = initialsForName(location.displayName ?? location.username ?? "??")
        return ZStack {
            Circle()
                .fill(AppTheme.brandAccent)
                .frame(width: 32, height: 32)
            Text(initials)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
        }
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.9), lineWidth: 2)
        )
    }

    private func memberAvatarView(name: String) -> some View {
        let initials = initialsForName(name)
        return ZStack {
            Circle()
                .fill(AppTheme.surfaceField)
                .frame(width: 42, height: 42)
            Text(initials)
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)
        }
    }

    private func initialsForName(_ name: String) -> String {
        let parts = name
            .split(separator: " ")
            .prefix(2)
            .map { String($0.prefix(1)) }
        let initials = parts.joined()
        return initials.isEmpty ? "?" : initials.uppercased()
    }

    private func presenceBadge(_ presence: ConvoyPresence) -> some View {
        let text: String
        let color: Color

        if presence.muted {
            text = "Muted"
            color = .orange
        } else if presence.listening {
            text = "Listening"
            color = .green
        } else {
            text = "Offline"
            color = .secondary
        }

        return Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.85))
            .clipShape(Capsule())
    }

    private func canRemoveMember(_ member: ConvoyMember) -> Bool {
        guard let membershipRole else { return false }
        if member.role == .owner { return false }
        if membershipRole == .admin && member.role == .admin { return false }
        return true
    }

    private func updateMapRegion(with locations: [ConvoyLocation]) {
        guard !locations.isEmpty else { return }
        let latitudes = locations.map(\.latitude)
        let longitudes = locations.map(\.longitude)
        guard let minLat = latitudes.min(),
              let maxLat = latitudes.max(),
              let minLon = longitudes.min(),
              let maxLon = longitudes.max() else {
            return
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )

        let span = MKCoordinateSpan(
            latitudeDelta: max(0.01, (maxLat - minLat) * 1.6),
            longitudeDelta: max(0.01, (maxLon - minLon) * 1.6)
        )

        mapRegion = MKCoordinateRegion(center: center, span: span)
    }
}

private struct PTTButton: View {
    let isActive: Bool
    let isEnabled: Bool
    let onPress: () -> Void
    let onRelease: () -> Void

    @State private var hasPressed = false

    var body: some View {
        Text(buttonTitle)
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(buttonColor)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
            .allowsHitTesting(isEnabled)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard isEnabled, !hasPressed else { return }
                        hasPressed = true
                        onPress()
                    }
                    .onEnded { _ in
                        if hasPressed && isEnabled {
                            onRelease()
                        }
                        hasPressed = false
                    }
            )
    }

    private var buttonTitle: String {
        if !isEnabled {
            return "Connect to talk"
        }
        return isActive ? "Transmitting... Release to stop" : "Hold to Talk"
    }

    private var buttonColor: Color {
        if !isEnabled {
            return AppTheme.buttonDisabled
        }
        return isActive ? Color.green : AppTheme.brandAccent
    }
}

private struct MessageBanner: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.footnote.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private extension String {
    var trimmedNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
