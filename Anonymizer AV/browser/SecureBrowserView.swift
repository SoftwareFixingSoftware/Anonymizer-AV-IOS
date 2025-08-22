// === SecureBrowserView.swift ===
import SwiftUI
@preconcurrency import WebKit

/// SwiftUI view that mirrors SecureBrowserFragment behaviour.
/// Use SecureBrowserView() in your SwiftUI layout.
public struct SecureBrowserView: UIViewRepresentable {
    public init() {}

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    public func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        if #available(iOS 14.0, *) {
            let pagePrefs = WKWebpagePreferences()
            pagePrefs.allowsContentJavaScript = true
            config.defaultWebpagePreferences = pagePrefs
        }
        config.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        // Reduce input assistant UI (helpful to quiet some system logs)
        if #available(iOS 15.0, *) {
            webView.inputAssistantItem.leadingBarButtonGroups = []
            webView.inputAssistantItem.trailingBarButtonGroups = []
        }

        // Load home page
        if let home = URL(string: "https://google.com") {
            webView.load(URLRequest(url: home))
        }

        return webView
    }

    public func updateUIView(_ uiView: WKWebView, context: Context) {}

    // Coordinator implementing the navigation decision logic.
    public final class Coordinator: NSObject, WKNavigationDelegate {
        private let parent: SecureBrowserView
        private var safetyCache: [String: Bool] = [:] // url -> safe?
        private let threatDetector = UrlAndWifiThreatDetector.shared

        init(_ parent: SecureBrowserView) {
            self.parent = parent
            super.init()
        }

        public func webView(_ webView: WKWebView,
                            decidePolicyFor navigationAction: WKNavigationAction,
                            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {

            guard let requestURL = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            let fullUrl = requestURL.absoluteString.lowercased()
            let host = requestURL.host?.lowercased() ?? ""

            // 1) Search engine detection
            if host.contains("google.com") || host.contains("bing.com") || host.contains("yahoo.com") {
                let comps = URLComponents(url: requestURL, resolvingAgainstBaseURL: false)
                var queryValue = comps?.queryItems?.first(where: { $0.name == "q" })?.value
                if (queryValue ?? "").isEmpty {
                    queryValue = comps?.queryItems?.first(where: { $0.name == "p" })?.value
                }
                let candidate = (queryValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !candidate.isEmpty {
                    // If the query itself is locally malicious -> block immediately
                    if threatDetector.isLocalMalicious(urlOrDomain: candidate) {
                        showBlockedPage(on: webView, blockedUrl: candidate)
                        decisionHandler(.cancel)
                        return
                    }
                    // Allow navigation immediately and schedule remote check in background (do not block browsing)
                    decisionHandler(.allow)
                    runRemoteCheckForCandidate(candidate, webView: webView, originalURL: requestURL)
                    return
                }
                decisionHandler(.allow)
                return
            }

            // 2) Local blacklist on host or full URL -> block immediately
            if threatDetector.isLocalMalicious(urlOrDomain: host) || threatDetector.isLocalMalicious(urlOrDomain: fullUrl) {
                showBlockedPage(on: webView, blockedUrl: fullUrl)
                decisionHandler(.cancel)
                return
            }

            // 3) Cached safety decision
            if let cachedSafe = safetyCache[fullUrl] {
                decisionHandler(cachedSafe ? .allow : .cancel)
                return
            }

            // 4) Not in cache: allow browsing now, run remote check in background and block later if unsafe
            decisionHandler(.allow)
            SafeBrowsingChecker.isUrlUnsafe(fullUrl) { isUnsafe in
                DispatchQueue.main.async {
                    self.safetyCache[fullUrl] = !isUnsafe
                    if isUnsafe {
                        self.showBlockedPage(on: webView, blockedUrl: fullUrl)
                    }
                }
            }
        }

        // Run remote check for a search query candidate (only if candidate looks like a domain/url)
        private func runRemoteCheckForCandidate(_ candidate: String, webView: WKWebView, originalURL: URL) {
            // If candidate looks like a domain (contains dot), check remote; otherwise skip remote check.
            if !candidate.contains(".") {
                return
            }
            SafeBrowsingChecker.isUrlUnsafe(candidate) { isUnsafe in
                DispatchQueue.main.async {
                    if isUnsafe {
                        self.showBlockedPage(on: webView, blockedUrl: candidate)
                    } else {
                        // If the original navigation was cancelled earlier and not already loaded,
                        // ensure it's loaded. (Here we allow navigation so it will already be loading.)
                        if webView.url == nil || webView.url == originalURL {
                            webView.load(URLRequest(url: originalURL))
                        }
                    }
                }
            }
        }

        private func showBlockedPage(on webView: WKWebView, blockedUrl: String) {
            let safeEncoded = blockedUrl.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? blockedUrl
            let html = """
            <html><body style='background-color:#ff4444;color:white;text-align:center;padding-top:50px;'>
              <h1>⚠ Unsafe Website Blocked</h1>
              <p>The site you tried to visit has been flagged as unsafe.</p>
              <p><b>\(safeEncoded)</b></p>
            </body></html>
            """
            webView.loadHTMLString(html, baseURL: nil)
        }
    }
}
