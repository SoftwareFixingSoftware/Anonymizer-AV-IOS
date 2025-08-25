import SwiftUI
import AVFoundation

let detector = UrlAndWifiThreatDetector.shared

struct QrScannerView: View {
    @State private var scannedCode: String = ""
    @State private var alertMessage: String = ""
    @State private var showAlert: Bool = false
    @State private var isScanning: Bool = false
    @State private var manualUrl: String = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("QR Scanner / Manual URL")
                .font(.largeTitle)
                .padding(.top)

            Text(isScanning ? "Scanning..." : "Ready.")
                .font(.headline)

            Button(action: startScan) {
                Text(isScanning ? "Scanning..." : "Scan QR Code")
                    .frame(maxWidth: .infinity)
            }
            .disabled(isScanning)
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)

            TextField("Or enter URL manually", text: $manualUrl)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            Button("Open URL") {
                guard !manualUrl.isEmpty else { return }
                print("[DEBUG] Manual URL entered: \(manualUrl)")
                handleQr(manualUrl)
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)

            if !scannedCode.isEmpty {
                ScrollView {
                    Text(scannedCode)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                }
                .frame(maxHeight: 200)
            }
        }
        .padding()
        .alert(alertMessage, isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        }
    }

    private func startScan() {
        isScanning = true
        scannedCode = ""
        print("[DEBUG] Starting QR scan...")

        let scanner = QRCodeScannerController { payload in
            DispatchQueue.main.async {
                self.isScanning = false
                print("[DEBUG] QR scan result: \(payload)")
                self.handleQr(payload)
            }
        }
        scanner.startScanning()
    }

    private func handleQr(_ payload: String) {
        scannedCode = payload
        print("[DEBUG] Handling payload: \(payload)")

        // Check local blacklists
        if detector.isLocalMalicious(urlOrDomain: payload) || detector.isMaliciousSsid(payload) {
            alertMessage = "Blocked: QR contains malicious content."
            print("[DEBUG] Blocked by local blacklist")
            showAlert = true
            return
        }

        // Prepend https:// if it's just a domain without scheme
        var urlString = payload
        if !urlString.lowercased().hasPrefix("http://") &&
            !urlString.lowercased().hasPrefix("https://") {
            urlString = "https://\(urlString)"
            print("[DEBUG] Prepending https://, new URL: \(urlString)")
        }

        guard let url = URL(string: urlString),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            alertMessage = "Invalid URL: \(payload)"
            print("[DEBUG] Not a valid HTTP/HTTPS URL even after prepending scheme")
            showAlert = true
            return
        }

        // Resolve redirects
        resolveRedirects(url) { finalUrl in
            DispatchQueue.main.async {
                print("[DEBUG] Final resolved URL: \(finalUrl)")

                if detector.isLocalMalicious(urlOrDomain: finalUrl) {
                    self.alertMessage = "Blocked: Final URL is malicious."
                    print("[DEBUG] Final URL blocked by local blacklist")
                    self.showAlert = true
                    return
                }

                self.alertMessage = "QR OK — Opening URL: \(finalUrl)"
                self.showAlert = true

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if let safeURL = URL(string: finalUrl),
                       UIApplication.shared.canOpenURL(safeURL) {
                        UIApplication.shared.open(safeURL, options: [:]) { success in
                            print("[DEBUG] Attempted to open URL: \(safeURL), success: \(success)")
                        }
                    } else {
                        print("[DEBUG] Cannot open URL: \(finalUrl)")
                    }
                }
            }
        }
    }

    // MARK: - Resolve Redirects
    private func resolveRedirects(_ url: URL, completion: @escaping (String) -> Void) {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 7.0

        let task = URLSession.shared.dataTask(with: request) { _, response, _ in
            if let httpResponse = response as? HTTPURLResponse,
               (300..<400).contains(httpResponse.statusCode),
               let location = httpResponse.allHeaderFields["Location"] as? String,
               let nextURL = URL(string: location, relativeTo: url) {
                print("[DEBUG] Redirect found: \(url) -> \(nextURL)")
                resolveRedirects(nextURL, completion: completion)
            } else {
                completion(url.absoluteString)
            }
        }
        task.resume()
    }
}

// MARK: - QR Code Scanner Controller (AVFoundation)
final class QRCodeScannerController: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    private let session = AVCaptureSession()
    private let callback: (String) -> Void

    init(callback: @escaping (String) -> Void) {
        self.callback = callback
        super.init()
    }

    func startScanning() {
        guard let device = AVCaptureDevice.default(for: .video) else {
            callback("Camera unavailable")
            print("[DEBUG] Camera unavailable")
            return
        }

        guard let input = try? AVCaptureDeviceInput(device: device) else {
            callback("Cannot create input")
            print("[DEBUG] Cannot create AVCapture input")
            return
        }

        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
        output.metadataObjectTypes = [.qr]

        session.startRunning()
        print("[DEBUG] AVCapture session started")
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        if let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
           let payload = obj.stringValue {
            session.stopRunning()
            print("[DEBUG] QR code detected: \(payload)")
            callback(payload)
        }
    }
}
