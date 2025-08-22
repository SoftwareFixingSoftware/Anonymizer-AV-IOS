// === SafeBrowsingChecker.swift ===
import Foundation

/// Async Google Safe Browsing v4 client.
/// completion(true) -> URL is unsafe (matches exist).
public final class SafeBrowsingChecker {
    // Replace with your own API key for production.
    private static let apiKey = "AIzaSyDFmnkNmMVM5-Us-SDxzomm_02ZzQiK2xs"
    private static let endpointBase = "https://safebrowsing.googleapis.com/v4/threatMatches:find?key="

    /// Calls Google Safe Browsing. completion(true) means **unsafe** (there are matches).
    public static func isUrlUnsafe(_ urlToCheck: String, completion: @escaping (Bool) -> Void) {
        guard let endpoint = URL(string: endpointBase + apiKey) else {
            completion(false)
            return
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "client": ["clientId": "luke-ios", "clientVersion": "1.0"],
            "threatInfo": [
                "threatTypes": ["MALWARE", "SOCIAL_ENGINEERING", "UNWANTED_SOFTWARE", "POTENTIALLY_HARMFUL_APPLICATION"],
                "platformTypes": ["ANY_PLATFORM"],
                "threatEntries": [["url": urlToCheck]]
            ]
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            completion(false)
            return
        }

        let task = URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data else {
                completion(false)
                return
            }

            if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let matches = json["matches"] as? [Any], matches.count > 0 {
                completion(true)
            } else {
                completion(false)
            }
        }
        task.resume()
    }
}
