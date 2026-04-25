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
    @State private var isLoggedIn = false

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
                if isLoggedIn {
                    ContentView()
                } else {
                    LoginView(isLoggedIn: $isLoggedIn)
                }
            }
            .onOpenURL { url in
                Task {
                    try? await supabase.auth.session(from: url)
                    if let _ = try? await supabase.auth.session {
                        await MainActor.run { isLoggedIn = true }
                    }
                }
            }
        }
        .modelContainer(sharedModelContainer)
    }
}
