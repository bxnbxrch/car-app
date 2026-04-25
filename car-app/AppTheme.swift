import SwiftUI

enum AppTheme {
    static let brandAccent = Color("BrandAccent")
    static let brandAccentGlow = Color("BrandAccentGlow")
    static let backgroundPrimary = Color("BackgroundPrimary")
    static let backgroundGradientTop = Color("BackgroundGradientTop")
    static let backgroundGradientMiddle = Color("BackgroundGradientMiddle")
    static let backgroundGradientBottom = Color("BackgroundGradientBottom")
    static let surfaceCard = Color("SurfaceCard")
    static let surfaceField = Color("SurfaceField")
    static let surfaceSecondary = Color("SurfaceSecondary")
    static let textPrimary = Color("TextPrimary")
    static let textSecondary = Color("TextSecondary")
    static let borderSubtle = Color("BorderSubtle")
    static let borderAccent = Color("BorderAccent")
    static let buttonDisabled = Color("ButtonDisabled")
    static let googleButtonBackground = Color("GoogleButtonBackground")
    static let glassHighlight = Color("GlassHighlight")

    static let cardCornerRadius: CGFloat = 28
    static let fieldCornerRadius: CGFloat = 16
    static let buttonCornerRadius: CGFloat = 16

    static let appBackground = LinearGradient(
        colors: [
            backgroundGradientTop,
            backgroundGradientMiddle,
            backgroundGradientBottom
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
