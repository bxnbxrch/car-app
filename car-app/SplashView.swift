import SwiftUI

struct SplashView: View {
    var body: some View {
        ZStack {
            AppTheme.appBackground
                .ignoresSafeArea()

            Circle()
                .fill(AppTheme.brandAccentGlow)
                .frame(width: 260, height: 260)
                .blur(radius: 36)
                .offset(y: -36)

            VStack(spacing: 24) {
                Image("driveout-logo")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 260)
                    .accessibilityLabel("Driveout logo")

                ProgressView()
                    .tint(AppTheme.brandAccent)
                    .scaleEffect(1.1)
            }
            .padding(32)
        }
    }
}

#Preview("Light") {
    SplashView()
}

#Preview("Dark") {
    SplashView()
        .preferredColorScheme(.dark)
}
