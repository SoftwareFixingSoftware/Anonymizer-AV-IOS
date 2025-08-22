// === UrlAndWifiThreatDetector.swift ===
import Foundation

/// Mirrors Android UrlAndWifiThreatDetector behavior:
/// - loads local blacklists (from bundled files if present),
/// - maintains trusted domains,
/// - performs quick local checks (domain equality / suffix / contains),
/// - offers async remote check via SafeBrowsingChecker (called from other code).
public final class UrlAndWifiThreatDetector {
    public static let shared = UrlAndWifiThreatDetector()

    private var urlIndicators: Set<String> = []
    private var ssidIndicators: Set<String> = []
    private var trustedDomains: Set<String> = []

    private init() {
        loadAssetLinesToSet(resourceName: "url_blacklist", into: &urlIndicators, treatAsUrl: true)
        loadAssetLinesToSet(resourceName: "wifi_blacklist", into: &ssidIndicators, treatAsUrl: false)
        loadTrustedDomains()

        if urlIndicators.isEmpty {
            urlIndicators.insert("admin-backdoor-shell.com")
            urlIndicators.insert("exploit-kit-download.net")
        }
        if ssidIndicators.isEmpty {
            ssidIndicators.insert("free wifi")
            ssidIndicators.insert("public wifi")
        }
    }

    // MARK: - Asset loading
    private func loadAssetLinesToSet(resourceName: String, into set: inout Set<String>, treatAsUrl: Bool) {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "txt"),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return
        }

        text.components(separatedBy: .newlines).forEach { line in
            var s = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if s.isEmpty { return }
            if s.hasPrefix("#") { return }

            if treatAsUrl {
                if let h = hostFromString(s) { s = h } else { s = s.lowercased() }
            } else {
                s = s.lowercased()
            }
            set.insert(s)
        }
    }

    private func loadTrustedDomains() {
        let defaults = ["google.com", "bing.com", "duckduckgo.com", "yahoo.com", "baidu.com"]
        trustedDomains.formUnion(defaults)
    }

    private func hostFromString(_ input: String) -> String? {
        if let u = URL(string: input), let h = u.host?.lowercased() { return h }
        var s = input.lowercased()
        if s.hasPrefix("http://") { s = String(s.dropFirst(7)) }
        if s.hasPrefix("https://") { s = String(s.dropFirst(8)) }
        if s.hasPrefix("www.") { s = String(s.dropFirst(4)) }
        if let slash = s.firstIndex(of: "/") { s = String(s[..<slash]) }
        return s.isEmpty ? nil : s
    }

    private func extractBaseDomain(from rawUrl: String) -> String {
        if let host = URL(string: rawUrl)?.host?.lowercased() { return host }
        return hostFromString(rawUrl) ?? rawUrl.lowercased()
    }

    // MARK: - Public API
    public func isTrustedDomain(_ domain: String) -> Bool {
        let d = domain.lowercased()
        for trusted in trustedDomains {
            if d == trusted || d.hasSuffix("." + trusted) { return true }
        }
        return false
    }

    /// Local-only quick blacklist check (domain equality/suffix or contains indicator).
    public func isLocalMalicious(urlOrDomain raw: String) -> Bool {
        let rawLower = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let domain = extractBaseDomain(from: rawLower)
        if isTrustedDomain(domain) { return false }

        for indicator in urlIndicators {
            guard !indicator.isEmpty else { continue }
            if domain == indicator { return true }
            if domain.hasSuffix("." + indicator) { return true }
            if rawLower.contains(indicator) { return true }
        }
        return false
    }

    /// Allow adding local indicators at runtime
    public func addUrlThreat(_ indicator: String) {
        let s = indicator.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }
        if let h = hostFromString(s) { urlIndicators.insert(h) } else { urlIndicators.insert(s) }
    }

    public func addWifiThreat(_ indicator: String) {
        let s = indicator.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }
        ssidIndicators.insert(s)
    }

    public func isMaliciousSsid(_ ssidRaw: String) -> Bool {
        let s = ssidRaw.replacingOccurrences(of: "\"", with: "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for indicator in ssidIndicators {
            if s.contains(indicator) { return true }
        }
        return false
    }
}
