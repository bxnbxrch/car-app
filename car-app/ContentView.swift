//
//  ContentView.swift
//  car-app
//
//  Created by Ben Birch on 25/04/2026.
//

import SwiftUI
import SwiftData
import PhotosUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [Item]

    var body: some View {
        NavigationSplitView {
            List {
                ForEach(items) { item in
                    NavigationLink {
                        Text("Item at \(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))")
                    } label: {
                        Text(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
                    }
                }
                .onDelete(perform: deleteItems)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
                ToolbarItem {
                    Button(action: addItem) {
                        Label("Add Item", systemImage: "plus")
                    }
                }
            }
        } detail: {
            VStack(spacing: 24) {
                Image("driveout-logo-darkmode")
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 280)

                Text("Select an item")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }

    private func addItem() {
        withAnimation {
            let newItem = Item(timestamp: Date())
            modelContext.insert(newItem)
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(items[index])
            }
        }
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
}

struct PostLoginOnboardingView: View {
    enum Step: Int, CaseIterable {
        case username
        case informalName
        case profilePhoto
        case carType
    }

    let onComplete: (OnboardingProfilePayload) -> Void

    @State private var step: Step = .username
    @State private var username = ""
    @State private var informalName = ""
    @State private var carType = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var avatarData: Data?
    @State private var avatarUIImage: UIImage?
    @State private var isLoadingPhoto = false

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
                .foregroundStyle(.secondary)

            ProgressView(value: Double(step.rawValue + 1), total: Double(Step.allCases.count))
                .tint(Color(red: 0.05, green: 0.5, blue: 1.0))
        }
    }

    private var usernameStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pick a unique username")
                .font(.title2)
                .fontWeight(.semibold)

            Text("This should be unique. You can use lowercase letters, numbers, and underscores.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("e.g. ben_drives", text: $username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding()
                .background(Color(.secondarySystemBackground))
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
                .foregroundStyle(.secondary)

            TextField("e.g. Ben", text: $informalName)
                .padding()
                .background(Color(.secondarySystemBackground))
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
                .foregroundStyle(.secondary)

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
                .background(Color(.secondarySystemBackground))
                .clipShape(Circle())

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Text(isLoadingPhoto ? "Loading photo..." : "Choose Photo")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(red: 0.05, green: 0.5, blue: 1.0))
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
                .foregroundStyle(.secondary)

            TextField("e.g. Tesla Model 3", text: $carType)
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var navigationButtons: some View {
        VStack(spacing: 10) {
            Button(action: advance) {
                Text(step == .carType ? "Finish" : "Continue")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(canContinue ? Color(red: 0.05, green: 0.5, blue: 1.0) : Color.gray.opacity(0.4))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!canContinue)

            if step.rawValue > 0 {
                Button("Back") {
                    step = Step(rawValue: step.rawValue - 1) ?? .username
                }
                .frame(maxWidth: .infinity)
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
            let payload = OnboardingProfilePayload(
                username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                informalName: informalName.trimmingCharacters(in: .whitespacesAndNewlines),
                avatarBase64: avatarData.base64EncodedString(),
                carType: carType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil
                    : carType.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            onComplete(payload)
            return
        }

        step = Step(rawValue: step.rawValue + 1) ?? .carType
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
