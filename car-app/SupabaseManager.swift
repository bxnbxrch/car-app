//
//  SupabaseManager.swift
//  car-app
//

import Foundation
import Supabase

let supabase = SupabaseClient(
    supabaseURL: URL(string: "https://fluritbenwgztxhaukhy.supabase.co")!,
    supabaseKey: "sb_publishable_7BMmdzf3IZiXk51rGYPUHA_OZ049Pe0",
    options: SupabaseClientOptions(
        auth: AuthClientOptions(
            emitLocalSessionAsInitialSession: true
        )
    )
)
