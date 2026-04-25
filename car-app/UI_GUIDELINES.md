# UI Guidelines

This file defines the UI structure and styling rules for the `car-app` iOS project.

## Core Rules

- Use `SwiftUI` for app interfaces.
- Reuse shared theme tokens instead of hardcoding colors in views.
- Keep light mode and dark mode behavior inside `Assets.xcassets` and `AppTheme.swift`.
- Prefer semantic styling like `AppTheme.textPrimary` over raw values like `Color(red:...)`.
- Match the existing visual language unless a specific redesign is requested.

## Theme System

### Source of Truth

- Shared UI tokens live in [AppTheme.swift](/Users/jack/Documents/car-app/car-app/car-app/AppTheme.swift:1).
- Semantic colors live in `car-app/Assets.xcassets`.
- Dark and light variants must be configured in the asset catalog, not scattered through view code.

### Required Pattern

When building new screens:

- Use `AppTheme.brandAccent` for primary accent actions.
- Use `AppTheme.textPrimary` and `AppTheme.textSecondary` for text.
- Use `AppTheme.surfaceCard`, `AppTheme.surfaceField`, and `AppTheme.surfaceSecondary` for surfaces.
- Use `AppTheme.borderSubtle` and `AppTheme.borderAccent` for outlines.
- Use `AppTheme.appBackground` or `AppTheme.backgroundPrimary` for screen backgrounds, depending on the screen.

### Avoid

- Do not add inline `Color(red:green:blue:)` values in feature views unless there is a strong reason.
- Do not branch on `colorScheme` in every view for normal palette decisions.
- Do not use `.preferredColorScheme(...)` in production UI unless the screen must force a mode.

## File Placement

Current project layout is small, so keep files organized by role.

### Existing Root UI Files

- `LoginView.swift`: authentication UI
- `SplashView.swift`: launch/splash UI
- `ContentView.swift`: main app content and onboarding flow
- `AppTheme.swift`: shared UI tokens and theme access

### Rules For New UI

- Put shared theme helpers in `AppTheme.swift` or a clearly related shared UI file.
- Put standalone screens in their own SwiftUI file.
- Name screen files after the screen, for example `ProfileView.swift`, `GarageView.swift`, `SettingsView.swift`.
- Keep one main view type per file unless the supporting types are tightly coupled and small.

### If The App Grows

If more screens are added, move toward feature folders such as:

- `Auth/`
- `Onboarding/`
- `Home/`
- `Profile/`
- `SharedUI/`

Until that becomes necessary, keep the current flat structure clean and consistent.

## View Construction

- Use `struct SomeView: View`.
- Use `@State private var` for local mutable state.
- Use `let` for immutable configuration passed into a view.
- Extract repeated UI into private computed properties or small helper views.
- Keep view code readable; do not leave large blocks of duplicated styling.

## Styling Conventions

- Use `foregroundStyle(...)` instead of older styling patterns when appropriate.
- Use shared corner radius values from `AppTheme` when available.
- Reuse the existing button and field styling patterns before inventing a new one.
- Use padding and spacing deliberately; avoid random per-screen values unless needed.

## Asset Rules

- Add new reusable colors to `Assets.xcassets` as named color sets.
- Give asset names semantic meaning, for example `TextPrimary`, `SurfaceCard`, `BrandAccent`.
- Do not create asset names tied to one screen unless they are truly screen-specific.
- Keep image assets named clearly and consistently with current project conventions.

## New Screen Checklist

Before finishing a new interface, check:

- Does it use `AppTheme` instead of raw palette values?
- Are light and dark mode handled through semantic assets?
- Is the file name clear and consistent?
- Is the UI split into sensible subviews or helper properties?
- Does it match the established look of the app?

## Validation

After UI changes:

- Run Xcode diagnostics on changed files.
- Build the project to confirm the app still compiles.
- Preview in both light mode and dark mode when the screen is visual.

## Default Expectation For Future Work

When creating a new UI in this repo:

1. Add any reusable colors to `Assets.xcassets`.
2. Expose them through `AppTheme.swift` if they are part of the shared design system.
3. Build the screen with semantic theme tokens.
4. Keep the file structure simple and consistent with the current app layout.
