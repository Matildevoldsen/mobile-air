import SwiftUI

/// A view that replicates the launch screen appearance.
/// This allows the app to appear launched while heavy initialization continues in the background.
struct SplashView: View {
    @ObservedObject private var appState = AppState.shared

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background color matching launch screen (white)
                Color.white
                    .ignoresSafeArea()

                // LaunchImage scaled to fill (matching LaunchScreen.storyboard scaleAspectFill)
                Image("LaunchImage")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .ignoresSafeArea()

                if let startupFailure = appState.startupFailure {
                    ScrollView {
                        Text(startupFailure)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundStyle(.white)
                            .textSelection(.enabled)
                            .padding(16)
                    }
                    .background(Color.red.opacity(0.95))
                    .ignoresSafeArea()
                }
            }
        }
        .ignoresSafeArea()
    }
}

#Preview {
    SplashView()
}
