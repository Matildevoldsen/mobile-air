import SwiftUI
import WebKit
import ObjectiveC.runtime

struct NativeDebugOverlay: View {
    @ObservedObject private var appState = AppState.shared

    let source: String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            ScrollView {
                Text(debugText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.green)
                    .textSelection(.enabled)
                    .padding(10)
            }
            .frame(width: 370, height: 300, alignment: .topLeading)
            .background(Color.black.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.green.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 4)
            .padding(.top, 52)
            .padding(.leading, 12)
        }
    }

    private var debugText: String {
        let startupFailure = appState.startupFailure ?? "(none)"

        return """
        NativePHP DEBUG HUD [\(source)]
        isReadyToLoad=\(appState.isReadyToLoad)
        isInitialized=\(appState.isInitialized)
        startupFailure=\(startupFailure)

        Recent logs:
        \(DebugLogger.shared.snapshot(lines: 30))
        """
    }
}

private final class KeyboardAccessoryHider: NSObject {
    @objc var noInputAccessoryView: Any? {
        nil
    }
}

extension NSNotification.Name {
    public static let reloadWebViewNotification = NSNotification.Name("ReloadWebViewNotification")
    public static let redirectToURLNotification = NSNotification.Name("RedirectToURLNotification")
    public static let navigateWithInertiaNotification = NSNotification.Name("NavigateWithInertiaNotification")
}

struct ContentView: View {
    @State private var phpOutput = ""
    @StateObject private var uiState = NativeUIState.shared

    var body: some View {
        NativeSideNavigation(onNavigate: handleNavigation) {
            WebViewLayoutContainer(onTabSelected: handleNavigation)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .top, spacing: 0) {
                    if uiState.hasTopBar() {
                        Color.clear.frame(height: 44)
                    }
                }
                .overlay(alignment: .top) {
                    if uiState.hasTopBar() {
                        NativeTopBar(onNavigate: handleNavigation)
                    }
                }
        }
    }

    /// Handle navigation from any UI component
    /// Uses Inertia router if available for SPA-like navigation, falls back to full page load
    private func handleNavigation(_ url: String) {
        // Check if this is an external HTTP/HTTPS URL
        if isExternalUrl(url) {
            // Open external URLs in the default browser
            if let externalUrl = URL(string: url) {
                UIApplication.shared.open(externalUrl)
            }
            return
        }

        // Handle internal navigation using Inertia if available
        let path = extractPath(url)

        NotificationCenter.default.post(
            name: .navigateWithInertiaNotification,
            object: nil,
            userInfo: ["path": path]
        )
    }

    /// Check if URL is external (absolute HTTP/HTTPS not pointing to localhost)
    private func isExternalUrl(_ url: String) -> Bool {
        return (url.hasPrefix("http://") || url.hasPrefix("https://"))
            && !url.contains("127.0.0.1")
            && !url.contains("localhost")
    }


    /// Extract path and query from URL, handling both full URLs and relative paths
    private func extractPath(_ url: String) -> String {
        if url.hasPrefix("php://") {
            // Extract just the path from php://127.0.0.1/path
            if let parsedUrl = URL(string: url) {
                let path = parsedUrl.path.isEmpty ? "/" : parsedUrl.path
                let query = parsedUrl.query
                let result = query != nil ? "\(path)?\(query!)" : path

                return result
            }
        }

        if url.hasPrefix("http://") || url.hasPrefix("https://") {
            // Parse as full URL and extract path + query
            if let parsedUrl = URL(string: url) {
                let path = parsedUrl.path.isEmpty ? "/" : parsedUrl.path
                let query = parsedUrl.query
                let result = query != nil ? "\(path)?\(query!)" : path

                return result
            }
        } else if url.hasPrefix("/") {
            return url
        } else {
            let result = "/\(url)"

            return result
        }

        // Fallback
        let fallback = url.hasPrefix("/") ? url : "/\(url)"

        return fallback
    }
}

/// Shared WKWebView instance holder to persist across view updates
class SharedWebView: ObservableObject {
    static let shared = SharedWebView()
    weak var webView: WKWebView?
    var coordinator: WebView.Coordinator?
}

/// Container that wraps a single WebView instance with appropriate layout based on UI state
struct WebViewLayoutContainer: View {
    @ObservedObject var uiState = NativeUIState.shared
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    let onTabSelected: (String) -> Void

    var body: some View {
        if uiState.hasBottomNav() {
            if #available(iOS 26.0, *) {
                // iOS 26+: WebView extends behind tab bar for Liquid Glass effect
                GeometryReader { geometry in
                    ZStack(alignment: .bottom) {
                        // Single WebView instance - extends to full screen
                        WebView(shared: SharedWebView.shared, horizontalSizeClass: horizontalSizeClass)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .ignoresSafeArea()
                            // Add bottom padding so content isn't hidden behind tab bar
                            .safeAreaInset(edge: .bottom) {
                                Color.clear
                                    .frame(height: 49 + geometry.safeAreaInsets.bottom)
                            }

                        // Bottom navigation overlays at bottom
                        NativeBottomNavigation(onTabSelected: onTabSelected)
                    }
                    .ignoresSafeArea()
                }
            } else {
                // iOS 18 and below: WebView stops at tab bar
                ZStack(alignment: .bottom) {
                    // Single WebView instance - fills available space
                    WebView(shared: SharedWebView.shared, horizontalSizeClass: horizontalSizeClass)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ignoresSafeArea(.all, edges: uiState.hasTopBar() ? .horizontal : .all)

                    // Bottom navigation at bottom
                    NativeBottomNavigation(onTabSelected: onTabSelected)
                }
            }
        } else {
            // No bottom nav - WebView fills entire screen
            WebView(shared: SharedWebView.shared, horizontalSizeClass: horizontalSizeClass)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.all, edges: uiState.hasTopBar() ? [.horizontal, .top, .bottom] : .all)
        }
    }
}

struct WebView: UIViewRepresentable {
    static let dataStore = WKWebsiteDataStore.nonPersistent()
    static func makeFreshRequest(url: URL) -> URLRequest {
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 30
        )
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        return request
    }
    let shared: SharedWebView
    let horizontalSizeClass: UserInterfaceSizeClass?

    func makeCoordinator() -> Coordinator {
        // Reuse existing coordinator if available to maintain LaravelBridge connection
        if let existingCoordinator = shared.coordinator {
            print("♻️ Reusing existing Coordinator")
            return existingCoordinator
        }

        print("🆕 Creating new Coordinator")
        let coordinator = Coordinator()
        shared.coordinator = coordinator
        return coordinator
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        // Don't remove observers or clear LaravelBridge when reusing the WebView
        // The shared instance will persist and we'll re-register in makeUIView if needed
        print("⚠️ dismantleUIView called - skipping observer removal for reused WebView")
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let logger = ConsoleLogger()
        var webView: WKWebView?
        var hasCompletedInitialLoad = false

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            let scheme = url.scheme?.lowercased() ?? ""

            // Rewrite http(s)://127.0.0.1 to php:// scheme — PHP/Symfony only understands
            // http/https so redirect()->intended() and $request->fullUrl() will always
            // produce http:// URLs for the local server. Route through the scheme handler's
            // redirect path which handles cookie injection from WKHTTPCookieStore.
            if (scheme == "http" || scheme == "https"),
               url.host == "127.0.0.1" {
                var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                components?.scheme = "php"
                if let phpURL = components?.url {
                    NotificationCenter.default.post(
                        name: .redirectToURLNotification,
                        object: nil,
                        userInfo: ["url": phpURL.absoluteString]
                    )
                }
                decisionHandler(.cancel)
                return
            }

            // Open external URLs and system schemes with the system handler
            if ["http", "https", "tel", "mailto", "sms", "facetime", "facetime-audio"].contains(scheme) {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            DebugLogger.shared.log("🌐 didCommit url=\(webView.url?.absoluteString ?? "unknown")")
            // Inject safe area insets IMMEDIATELY when navigation commits (before rendering)
            // This is the iOS equivalent of Android's onPageStarted
            injectSafeAreaInsets(webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DebugLogger.shared.log(
                "🌐 didFinish url=\(webView.url?.absoluteString ?? "unknown") title=\(webView.title ?? "(nil)")"
            )
            logPageSnapshot(webView, reason: "didFinish")

            // On first load, dismiss the splash screen
            if !hasCompletedInitialLoad {
                hasCompletedInitialLoad = true
                DispatchQueue.main.async {
                    AppState.shared.markInitialized()
                }
            }

            // Fade in WebView smoothly once initial page load is complete
            DispatchQueue.main.async {
                UIView.animate(withDuration: 0.2) {
                    webView.alpha = 1.0
                }
            }

            // Re-inject safe area insets to ensure they're set (like Android does)
            injectSafeAreaInsets(webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            showWebViewFailureOverlay(
                title: "WKWebView Navigation Failed",
                message: "\(error.localizedDescription)\nURL: \(webView.url?.absoluteString ?? "unknown")"
            )
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            // NSURLErrorCancelled (-999) is fired whenever we intentionally call
            // decisionHandler(.cancel) in decidePolicyFor (e.g. routing external https
            // URLs to the system browser, or stopping a load before redirecting).
            // These are expected — do not show the blocking error overlay for them.
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                return
            }
            showWebViewFailureOverlay(
                title: "WKWebView Provisional Navigation Failed",
                message: "\(error.localizedDescription)\nURL: \(webView.url?.absoluteString ?? "unknown")"
            )
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            showWebViewFailureOverlay(
                title: "WKWebView Process Terminated",
                message: "The web content process terminated unexpectedly."
            )
        }

        private func injectSafeAreaInsets(_ webView: WKWebView) {
            // Get insets from window scene (more reliable than webView.window which can be nil)
            let windowScene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first

            let insets = windowScene?.windows.first?.safeAreaInsets ?? webView.window?.safeAreaInsets ?? .zero

            // Also get color scheme for CSS variable
            let isDarkMode = windowScene?.windows.first?.traitCollection.userInterfaceStyle == .dark
            let colorScheme = isDarkMode ? "dark" : "light"

            let js = """
            (function() {
                // Set CSS variables directly on documentElement for immediate availability
                if (document.documentElement) {
                    document.documentElement.style.setProperty('--inset-top', '\(insets.top)px');
                    document.documentElement.style.setProperty('--inset-right', '\(insets.right)px');
                    document.documentElement.style.setProperty('--inset-bottom', '\(insets.bottom)px');
                    document.documentElement.style.setProperty('--inset-left', '\(insets.left)px');
                    document.documentElement.style.setProperty('--native-color-scheme', '\(colorScheme)');
                }
            })();
            """

            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        private func logPageSnapshot(_ webView: WKWebView, reason: String) {
            let js = """
            (function() {
                var body = document.body;
                var app = document.getElementById('app');

                return JSON.stringify({
                    href: window.location.href,
                    title: document.title || '',
                    readyState: document.readyState || '',
                    bodyChildCount: body ? body.children.length : -1,
                    bodyTextLength: body && body.innerText ? body.innerText.length : 0,
                    bodyHtmlLength: body && body.innerHTML ? body.innerHTML.length : 0,
                    appExists: !!app,
                    appChildCount: app ? app.children.length : -1,
                });
            })();
            """

            webView.evaluateJavaScript(js) { result, error in
                if let error {
                    DebugLogger.shared.log("🌐 page snapshot failed [\(reason)]: \(error.localizedDescription)")
                    return
                }

                if let snapshot = result as? String {
                    DebugLogger.shared.log("🌐 page snapshot [\(reason)]: \(snapshot)")
                } else {
                    DebugLogger.shared.log("🌐 page snapshot [\(reason)]: (non-string result)")
                }
            }
        }

        private func showWebViewFailureOverlay(title: String, message: String) {
            print("⚠️ \(title): \(message)")
            DebugLogger.shared.log("⚠️ \(title): \(message)")
            Task { @MainActor in
                AppState.shared.reportStartupFailure(title: title, detail: message)
            }

            DispatchQueue.main.async {
                guard let scene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first(where: { $0.activationState == .foregroundActive })
                    ?? UIApplication.shared.connectedScenes
                        .compactMap({ $0 as? UIWindowScene }).first,
                      let window = scene.windows.first(where: { $0.isKeyWindow })
                        ?? scene.windows.first else {
                    return
                }

                let overlayTag = 999_112

                if let existing = window.viewWithTag(overlayTag) as? UITextView {
                    existing.text = "\(title)\n\n\(message)"
                    return
                }

                let overlay = UITextView(frame: window.bounds)
                overlay.tag = overlayTag
                overlay.isEditable = false
                overlay.isSelectable = true
                overlay.backgroundColor = UIColor.systemRed.withAlphaComponent(0.96)
                overlay.textColor = .white
                overlay.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
                overlay.textContainerInset = UIEdgeInsets(top: 18, left: 16, bottom: 18, right: 16)
                overlay.text = "\(title)\n\n\(message)"
                overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]

                window.addSubview(overlay)
                window.bringSubviewToFront(overlay)
            }
        }

        @MainActor
        func notifyLaravel(
            event: String,
            payload: [String: Any]
        ) {
            let event: String = {
                let data = try! JSONSerialization.data(withJSONObject: [event])
                var literal = String(data: data, encoding: .utf8)!
                literal.removeFirst()
                literal.removeLast()
                return literal
            }()

            // 1. Inject JS event into the current web page
            if let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: []),
               let jsonString = String(data: jsonData, encoding: .utf8) {

                let js = """
                (function() {
                    const event = new CustomEvent(
                        "native-event",
                        {
                            detail: {
                                event: \(event),
                                payload: \(jsonString),
                            },
                        }
                    );
                    document.dispatchEvent(event);

                    fetch('/_native/api/events', {
                        method: 'POST',
                        headers: {
                            'Content-Type': 'application/json',
                            'X-Requested-With': 'XMLHttpRequest'
                        },
                        body: JSON.stringify({
                            event: \(event),
                            payload: \(jsonString),
                        })
                    }).then(response => response.json())
                      .then(data => console.log("API Event Dispatch Success:", JSON.stringify(data, null, 2)))
                      .catch(error => console.error("API Event Dispatch Error:", error));
                })();
                """

                self.webView?.evaluateJavaScript(js) { result, error in
                    if let error = error {
                        print("JavaScript injection error injecting event '\(event)': \(error)")
                    } else {
                        print("JavaScript event '\(event)' dispatched.")
                    }
                }

                // FUTURE: Send a request to Laravel backend directly
//                let request = RequestData(
//                    method: "POST",
//                    uri: "php://127.0.0.1/_native/api/events",
//                    data: jsonString,
//                    headers: [
//                        "Content-Type": "application/json"
//                    ])
//
//                _ = NativePHPApp.laravel(request: request)

            }
        }

        @objc func reloadWebView() {
            _ = NativePHPApp.shared?.artisan(additionalArgs: ["view:clear"])

            if let url = self.webView?.url {
                self.webView?.load(WebView.makeFreshRequest(url: url))
            } else {
                self.webView?.reloadFromOrigin()
            }
        }

        // Swipe gestures disabled for back/forward navigation
        // @objc func handleSwipeLeft(_ gesture: UISwipeGestureRecognizer) {
        //     if let webView = gesture.view as? WKWebView, webView.canGoForward {
        //         webView.goForward()
        //     }
        // }

        // @objc func handleSwipeRight(_ gesture: UISwipeGestureRecognizer) {
        //     if let webView = gesture.view as? WKWebView, webView.canGoBack {
        //         webView.goBack()
        //     }
        // }

        @objc func redirectToURL(_ notification: Notification) {
            if let urlString = notification.userInfo?["url"] as? String {
                if let url = URL(string: urlString) {
                    // Stop any current loading before starting new request
                    if self.webView?.isLoading == true {
                        self.webView?.stopLoading()
                    }

                    self.webView?.load(WebView.makeFreshRequest(url: url))
                }
            }
        }

        /// NativePHP page navigation must use full WebView navigations under the php:// protocol.
        @objc func navigateWithInertia(_ notification: Notification) {
            guard let path = notification.userInfo?["path"] as? String else { return }

            // Escape the path for JavaScript string
            let escapedPath = path
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")

            let js = """
            (function() {
                var path = "\(escapedPath)";
                console.log('[NativePHP] Navigation requested:', path);

                if (path === '/native/open-search') {
                    window.dispatchEvent(new CustomEvent('native:open-search'));
                    return;
                }

                if (path === '/native/open-model-selector') {
                    window.dispatchEvent(new CustomEvent('native:open-model-selector'));
                    return;
                }

                if (path === '/native/open-sidebar') {
                    window.dispatchEvent(new CustomEvent('native:open-sidebar'));
                    return;
                }

                if (path === '/native/new-chat') {
                    window.location.assign('/');
                    return;
                }

                window.location.assign(path);
            })();
            """

            self.webView?.evaluateJavaScript(js, completionHandler: nil)
        }

        @objc func keyboardWillShow(_ notification: Notification) {
            let js = "document.body.classList.add('keyboard-visible');"
            self.webView?.evaluateJavaScript(js, completionHandler: nil)
        }

        @objc func keyboardWillHide(_ notification: Notification) {
            let js = "document.body.classList.remove('keyboard-visible');"
            self.webView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    func makeUIView(context: Context) -> WKWebView {
        let coordinator = context.coordinator

        // Reuse existing WebView if available (coordinator is also reused via makeCoordinator)
        if let existingWebView = shared.webView {
            print("♻️ Reusing existing WKWebView instance (coordinator already reused)")
            // Ensure coordinator has reference to webView
            coordinator.webView = existingWebView
            existingWebView.navigationDelegate = coordinator
            existingWebView.alpha = 1.0
            disableKeyboardAssistant(for: existingWebView)

            if let currentURL = existingWebView.url {
                existingWebView.load(WebView.makeFreshRequest(url: currentURL))
            }

            // Observers are still registered (we don't remove them in dismantleUIView)
            // LaravelBridge is still connected (we don't clear it in dismantleUIView)

            return existingWebView
        }

        print("🆕 Creating new WKWebView instance with new Coordinator")

        // Initialize the custom scheme handler
        let schemeHandler = PHPSchemeHandler()

        // Configure WKWebView with the custom scheme handler
        let webConfiguration = WKWebViewConfiguration()

        webConfiguration.websiteDataStore = WebView.dataStore
        webConfiguration.setURLSchemeHandler(schemeHandler, forURLScheme: "php")
        webConfiguration.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: webConfiguration)
        disableKeyboardAssistant(for: webView)

        // Store webView in coordinator and shared instance
        coordinator.webView = webView
        shared.webView = webView
        shared.coordinator = coordinator

        addDebugSupport(webView: webView, context: context)

        addNativeHelper(webView: webView)

        addSwipeGestureSupport(webView: webView, context: context)

        // Configure scrollView for proper safe area handling with viewport-fit=cover
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        let fallbackPath = Bundle.main.path(forResource: "index", ofType: "html")
        let fallbackURL = URL(fileURLWithPath: fallbackPath!)

        // Keep the WebView visible during startup so failed navigations do not
        // collapse into an indistinguishable blank white screen.
        webView.alpha = 1.0

        // Give AppDelegate time to process any launch deep links before deciding what to load
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            DebugLogger.shared.log("🌐 WebView setup after AppDelegate delay")

            // Check for pending deep link BEFORE marking ready
            // (marking ready might process and clear the pending URL immediately)
            let hasPendingDeepLink = DeepLinkRouter.shared.hasPendingURL()

            // Mark WebView as ready (this may trigger pending URL processing)
            DeepLinkRouter.shared.markWebViewReady()

            // Only load default URL if there was no pending deep link
            if !hasPendingDeepLink {
                DebugLogger.shared.log("🌐 No pending deep link, loading default URL")
                let startPath = NativePHPApp.getStartURL()
                let startPage = URL(string: "php://127.0.0.1\(startPath)")
                webView.load(WebView.makeFreshRequest(url: startPage ?? fallbackURL))
            } else {
                DebugLogger.shared.log("🌐 Pending deep link detected, skipping default URL load")
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) {
            if webView.url == nil && !webView.isLoading {
                DebugLogger.shared.log("🌐 Fallback load triggered because WKWebView has no URL after startup")
                let startPath = NativePHPApp.getStartURL()
                let startPage = URL(string: "php://127.0.0.1\(startPath)")
                webView.load(WebView.makeFreshRequest(url: startPage ?? fallbackURL))
            }
        }

        // Setup Laravel bridge - use shared coordinator so it persists
        LaravelBridge.shared.send = { [weak shared] event, payload in
            Task { @MainActor in
                shared?.coordinator?.notifyLaravel(event: event, payload: payload as [String : Any])
            }
        }

        // Register NotificationCenter observers
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.reloadWebView),
            name: .reloadWebViewNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.redirectToURL),
            name: .redirectToURLNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.navigateWithInertia),
            name: .navigateWithInertiaNotification,
            object: nil
        )

        // Keyboard visibility observers
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.keyboardWillShow),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.keyboardWillHide),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )

        return webView
    }

    private func disableKeyboardAssistant(for webView: WKWebView) {
        let inputAssistantItem = webView.inputAssistantItem
        inputAssistantItem.leadingBarButtonGroups = []
        inputAssistantItem.trailingBarButtonGroups = []
        removeFormAccessoryBar(from: webView)
    }

    private func removeFormAccessoryBar(from webView: WKWebView) {
        guard let targetView = webView.scrollView.subviews.first(where: {
            NSStringFromClass(type(of: $0)).hasPrefix("WKContent")
        }) else {
            return
        }

        guard let targetViewClass = object_getClass(targetView) else {
            return
        }

        let subclassName = "\(NSStringFromClass(targetViewClass).replacingOccurrences(of: ".", with: "_"))_NoInputAccessoryView"

        if let existingClass = NSClassFromString(subclassName) {
            object_setClass(targetView, existingClass)
            targetView.reloadInputViews()
            return
        }

        guard let subclass = objc_allocateClassPair(targetViewClass, subclassName, 0),
              let method = class_getInstanceMethod(
                  KeyboardAccessoryHider.self,
                  #selector(getter: KeyboardAccessoryHider.noInputAccessoryView)
              ) else {
            return
        }

        class_addMethod(
            subclass,
            #selector(getter: UIResponder.inputAccessoryView),
            method_getImplementation(method),
            method_getTypeEncoding(method)
        )
        objc_registerClassPair(subclass)
        object_setClass(targetView, subclass)
        targetView.reloadInputViews()
    }

    func addDebugSupport(webView: WKWebView, context: Context) {
        #if DEBUG
        let userContentController = webView.configuration.userContentController
        let consoleLoggingScript = """
        (function() {
            function post(type, message) {
                try {
                    window.webkit.messageHandlers.console.postMessage({ type: type, message: message });
                } catch (e) {
                    // ignore native bridge logging failures
                }
            }

            function stringify(value) {
                if (typeof value === 'string') {
                    return value;
                }

                try {
                    return JSON.stringify(value);
                } catch (error) {
                    return String(value);
                }
            }

            function capture(type) {
                var old = console[type];
                console[type] = function() {
                    var message = Array.prototype.slice.call(arguments).map(stringify).join(" ");
                    post(type, message);
                    old.apply(console, arguments);
                };
            }

            window.addEventListener('error', function(event) {
                post(
                    'error',
                    '[window.error] ' + (event.message || 'Unknown error')
                        + ' @ ' + (event.filename || '(inline)')
                        + ':' + (event.lineno || 0)
                        + ':' + (event.colno || 0)
                );
            });

            window.addEventListener('unhandledrejection', function(event) {
                var reason = event.reason;
                post('error', '[unhandledrejection] ' + stringify(reason));
            });

            document.addEventListener('DOMContentLoaded', function() {
                var app = document.getElementById('app');
                post(
                    'debug',
                    '[DOMContentLoaded] title=' + (document.title || '')
                        + ' href=' + window.location.href
                        + ' bodyChildren=' + (document.body ? document.body.children.length : -1)
                        + ' appExists=' + (!!app)
                );
            });

            ['log', 'warn', 'error', 'debug'].forEach(capture);
        })();
        """

        let userScript = WKUserScript(source: consoleLoggingScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        userContentController.addUserScript(userScript)
        userContentController.add(context.coordinator.logger, name: "console")

        webView.isInspectable = true
        #endif
    }

    func addNativeHelper(webView: WKWebView) {
        let contentController = webView.configuration.userContentController

        // Inject safe area CSS FIRST at document start to prevent layout jump
        let safeAreaCSS = """
        (function() {
            var style = document.createElement('style');
            style.textContent = ':root{--inset-top:env(safe-area-inset-top,0px);--inset-right:env(safe-area-inset-right,0px);--inset-bottom:env(safe-area-inset-bottom,0px);--inset-left:env(safe-area-inset-left,0px)}@media(orientation:landscape){.nativephp-safe-area{padding-right:var(--inset-right);padding-left:var(--inset-left)}}@media(orientation:portrait){.nativephp-safe-area{padding-top:var(--inset-top);padding-bottom:var(--inset-bottom)}}';
            (document.head || document.documentElement).appendChild(style);
        })();
        """
        let safeAreaScript = WKUserScript(
            source: safeAreaCSS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        contentController.addUserScript(safeAreaScript)

        // Inject Native helper and other functionality at document end
        let helper = """
        const Native = {
            on: (event, callback) => {
                document.addEventListener("native-event", function (e) {
                    event = event.replace(/^(\\\\)+/, '');
                    e.detail.event = e.detail.event.replace(/^(\\\\)+/, '');

                    if (event === e.detail.event) {
                        return callback(e.detail.payload, event);
                    }
                });
            },
        };

        window.Native = Native;

        document.addEventListener("native-event", function (e) {
            e.detail.event = e.detail.event.replace(/^(\\\\)+/, '');

            if (window.Livewire) {
                window.Livewire.dispatch('native:' + e.detail.event, e.detail.payload);
            }
        });

        (function() {
            // Add platform identifier class
            document.body.classList.add('nativephp-ios');

            // Disable text selection
            document.body.style.userSelect = "none";
        })();
        """
        let script = WKUserScript(
            source: helper,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        contentController.addUserScript(script)
    }

    func addSwipeGestureSupport(webView: WKWebView, context: Context) {
        webView.navigationDelegate = context.coordinator
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // No manual insets needed - safeAreaInset handles topbar automatically
        // Bottom nav uses its own safeAreaInset in WebViewLayoutContainer
    }
}

class ConsoleLogger: NSObject, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let body = message.body as? [String: Any],
           let type = body["type"] as? String,
           let logMessage = body["message"] as? String {
            DebugLogger.shared.log("JS \(type): \(logMessage)")
            print()
            print("JS \(type): \(logMessage)")
        }
    }
}
