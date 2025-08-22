// BreachScanView.swift
import SwiftUI

struct BreachScanView: View {
    @State private var email: String = ""
    @State private var scanning: Bool = false
    @State private var resultMessage: String?
    @State private var isBreached: Bool = false
    @State private var lottieColor: Color = .cyan
    @State private var animationSpeed: CGFloat = 1.5
    @State private var playAnimation: Bool = false   // control playback
    @State private var pulse: Bool = false           // controls glow pulse
    
    var body: some View {
        VStack(spacing: 24) {
            TextField("Enter email", text: $email)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .padding(.horizontal)
            
            Button(action: startScan) {
                Text(scanning ? "Scanning..." : "Check")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(scanning ? Color.gray : Color.blue)
                    .cornerRadius(12)
            }
            .disabled(scanning)
            .padding(.horizontal)
            
            ZStack {
                // 🔴 Pulsing glow if breached
                if isBreached {
                    Circle()
                        .fill(Color.red.opacity(0.4))
                        .frame(width: 220, height: 220)
                        .scaleEffect(pulse ? 1.2 : 0.8)
                        .opacity(pulse ? 0.0 : 1.0)
                        .animation(
                            Animation.easeOut(duration: 1.2)
                                .repeatForever(autoreverses: false),
                            value: pulse
                        )
                        .onAppear { pulse = true }
                        .onDisappear { pulse = false }
                }
                
                // ✅ Lottie animation
                LottieView(
                    name: "radar_scan",
                    loopMode: .loop,
                    speed: animationSpeed,
                    play: playAnimation
                )
                .frame(width: 200, height: 200)
                .background(lottieColor.opacity(0.2))
                .clipShape(Circle())
                .allowsHitTesting(false)
            }
            
            if let message = resultMessage {
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundColor(isBreached ? .red : .green)
                    .padding(.horizontal)
            }
            
            Spacer()
        }
        .padding(.top, 40)
        .navigationTitle("Breach Scan")
    }
    
    private func startScan() {
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            resultMessage = "⚠️ Please enter an email address."
            isBreached = false
            return
        }
        
        scanning = true
        animationSpeed = 1.5
        lottieColor = .cyan
        resultMessage = nil
        playAnimation = true
        isBreached = false
        pulse = false
        
        DispatchQueue.global().async {
            Thread.sleep(forTimeInterval: 1.5)
            let leakedPassword = findPasswordForEmail(email: email)
            
            DispatchQueue.main.async {
                if let leaked = leakedPassword {
                    animationSpeed = 2.0
                    lottieColor = .red
                    isBreached = true
                    resultMessage = "🚨 Breach Found\nLeaked password: \(mask(leaked))"
                    
                    // stop radar spin after 3s
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        playAnimation = false
                    }
                } else {
                    animationSpeed = 0.8
                    lottieColor = .green
                    isBreached = false
                    resultMessage = "✅ Safe (so far)\nYour email was not found in our breach list."
                    
                    // stop radar spin after 2s
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        playAnimation = false
                    }
                }
                scanning = false
            }
        }
    }
    
    private func mask(_ leaked: String) -> String {
        if leaked.count > 4 {
            let start = leaked.prefix(2)
            let end = leaked.suffix(2)
            return "\(start)****\(end)"
        }
        return leaked
    }
    
    private func findPasswordForEmail(email: String) -> String? {
        guard let path = Bundle.main.path(forResource: "breach1", ofType: "txt") else { return nil }
        let target = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let content = try String(contentsOfFile: path, encoding: .utf8)
            for line in content.split(separator: "\n") {
                var cleanLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if cleanLine.first == "\u{FEFF}" {
                    cleanLine.removeFirst()
                }
                let parts = cleanLine.split(separator: ":", maxSplits: 1)
                if parts.count == 2 {
                    let emailPart = parts[0].lowercased()
                    let passwordPart = String(parts[1])
                    if emailPart == target {
                        return passwordPart
                    }
                }
            }
        } catch {
            print("Error reading breach file: \(error)")
        }
        return nil
    }
}
