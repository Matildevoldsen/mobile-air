import SwiftUI

/// Manages the app initialization state.
/// Uses two phases:
/// 1. isReadyToLoad - deferred init complete, safe to render ContentView/WebView
/// 2. isInitialized - WebView has loaded, safe to dismiss splash
@MainActor
class AppState: ObservableObject {
    static let shared = AppState()

    /// Phase 1: Deferred initialization complete, WebView can be rendered and start loading
    @Published var isReadyToLoad = false

    /// Phase 2: WebView has finished loading, splash can be dismissed
    @Published var isInitialized = false

    /// When startup stalls before the first page loads, show diagnostics instead of a silent white screen.
    @Published var startupFailure: String?

    private var startupWatchdog: DispatchWorkItem?
    private var deferredInitializationStarted = false

    private init() {}

    func startDeferredInitialization(_ action: @escaping () -> Void) {
        guard !deferredInitializationStarted else {
            return
        }

        deferredInitializationStarted = true
        armStartupWatchdog()

        DispatchQueue.global(qos: .userInitiated).async {
            action()
        }
    }

    func armStartupWatchdog(timeout: TimeInterval = 12) {
        startupWatchdog?.cancel()

        let watchdog = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }

            guard !self.isInitialized else {
                return
            }

            self.reportStartupFailure(
                title: "iOS startup timed out",
                detail: """
                The app did not finish its first WebView load within \(Int(timeout)) seconds.
                isReadyToLoad=\(self.isReadyToLoad)
                isInitialized=\(self.isInitialized)

                Recent native logs:
                \(DebugLogger.shared.snapshot())
                """
            )
        }

        startupWatchdog = watchdog
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: watchdog)
    }

    func reportStartupFailure(title: String, detail: String) {
        let message = """
        \(title)

        \(detail)
        """

        DebugLogger.shared.log("❌ \(title): \(detail)")
        startupFailure = message
    }

    /// Mark that deferred initialization is complete and WebView can start loading
    func markReadyToLoad() {
        DebugLogger.shared.log("📱 AppState: ready to load WebView")
        isReadyToLoad = true
    }

    /// Mark that WebView has loaded and splash can be dismissed
    func markInitialized() {
        DebugLogger.shared.log("📱 AppState: marking as initialized")
        startupWatchdog?.cancel()
        startupWatchdog = nil
        startupFailure = nil

        withAnimation(.easeInOut(duration: 0.3)) {
            isInitialized = true
        }
    }
}
