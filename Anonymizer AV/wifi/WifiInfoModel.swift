import SwiftUI
import CoreLocation
import SystemConfiguration.CaptiveNetwork

// MARK: - Location Manager
final class LocationManager: NSObject, ObservableObject {
    private let manager = CLLocationManager()

    @Published var isLocationEnabled: Bool = false
    @Published var authorizationStatus: CLAuthorizationStatus

    override init() {
        self.authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        // Initial async check
        DispatchQueue.main.async { [weak self] in
            self?.updateLocationStatus()
        }
    }

    func requestAuthorizationIfNeeded() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else {
            updateLocationStatus()
        }
    }

    private func updateLocationStatus() {
        let enabled = CLLocationManager.locationServicesEnabled()
        let auth = manager.authorizationStatus
        DispatchQueue.main.async { [weak self] in
            self?.isLocationEnabled = enabled && (auth == .authorizedAlways || auth == .authorizedWhenInUse)
            self?.authorizationStatus = auth
        }
    }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updateLocationStatus()
    }
}

// MARK: - Wifi Helper
struct WifiHelper {
    static func currentSSID() -> String? {
        guard let interfaces = CNCopySupportedInterfaces() as? [String] else { return nil }
        for iface in interfaces {
            if let dict = CNCopyCurrentNetworkInfo(iface as CFString) as? [String: Any],
               let ssid = dict[kCNNetworkInfoKeySSID as String] as? String {
                return ssid
            }
        }
        return nil
    }
}

// MARK: - Wi-Fi Security View
struct WifiSecurityView: View {
    @State private var statusText: String = "Ready. Press 'Scan Wi-Fi' to analyze the current network."
    @State private var resultsText: String = ""
    @State private var isScanning: Bool = false
    @StateObject private var locationManager = LocationManager()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(statusText)
                .font(.headline)
                .padding(.top)

            ScrollView {
                Text(resultsText)
                    .font(.system(.body, design: .monospaced))
                    .padding()
            }
            .frame(maxHeight: 300)

            Button(action: scanWifi) {
                Text(isScanning ? "Scanning..." : "Scan Wi-Fi")
                    .frame(maxWidth: .infinity)
            }
            .disabled(isScanning)
            .buttonStyle(.borderedProminent)
            .padding(.bottom)
        }
        .padding()
        .onAppear {
            locationManager.requestAuthorizationIfNeeded()
        }
    }

    private func scanWifi() {
        guard locationManager.isLocationEnabled else {
            statusText = "Location services are OFF — required for Wi-Fi SSID access."
            resultsText = "Please enable GPS/Location and retry."
            return
        }

        isScanning = true
        statusText = "Scanning Wi-Fi — gathering network details..."
        resultsText = ""

        DispatchQueue.global(qos: .userInitiated).async {
            let ssid = WifiHelper.currentSSID() ?? "Unknown"
            let lowerSSID = ssid.lowercased()

            var resultBuilder = "SSID: \(ssid)\n"

            // Check blacklist
            if UrlAndWifiThreatDetector.shared.isMaliciousSsid(ssid) {
                resultBuilder += "\nALERT: SSID matches blacklist. Consider disconnecting.\n"
            }

            // Placeholders for info unavailable on iOS
            resultBuilder += """
            BSSID: Unavailable
            Signal: Unknown
            Link Speed: Unknown
            Frequency: Unknown
            Channel: Unknown
            Encryption: Unknown
            Device IP: Unknown
            Gateway: Unknown
            MAC (Device): Unavailable
            """

            DispatchQueue.main.async {
                resultsText = resultBuilder
                statusText = "Scan complete."
                isScanning = false
            }
        }
    }
}
