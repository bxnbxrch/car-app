import SwiftUI

struct SplashView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 160, height: 160)
                .accessibilityLabel("App logo")
        }
    }
}

#Preview {
    SplashView()
}
