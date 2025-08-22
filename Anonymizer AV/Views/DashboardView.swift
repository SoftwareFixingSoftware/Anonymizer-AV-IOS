//
//  DashboardView.swift
//  Anonymizer AV
//

import SwiftUI
import Charts

struct DashboardView: View {
    @Binding var selectedTab: Int
    @State private var lastScan: String = "No scans yet"
    @State private var threatsFound: Int = 0
    
    @State private var battery: Double = 50
    @State private var cpu: Double = 40
    @State private var memory: Double = 60
    
    @State private var path: [String] = []
    
    private let coreFeatures: [Feature] = [
        Feature(iconName: "shield.fill", title: "Real-time Protection", description: "Constantly scans"),
        Feature(iconName: "exclamationmark.shield.fill", title: "Breach Scan", description: "Assure your Data"),
        Feature(iconName: "magnifyingglass", title: "Deep Scan", description: "Thorough check"),
        Feature(iconName: "qrcode.viewfinder", title: "QR Code", description: "Clean scan"),
        Feature(iconName: "clock.fill", title: "Scan History", description: "Previous scans")
    ]
    
    private let securityAndTools: [Feature] = [
        Feature(iconName: "globe", title: "Secure Browser", description: "Private browsing"),
        Feature(iconName: "wifi", title: "Wifi", description: "Check traffic"),
        Feature(iconName: "speedometer", title: "Optimization", description: "Clean Duplicates"),
        Feature(iconName: "doc.text.magnifyingglass", title: "Logs", description: "Review history")
    ]
    
    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    
                    // Last Scan + Threats Card
                    QuarantineCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(lastScan)
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text("Threats found: \(threatsFound)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Scan Now Button (kept accent color)
                    Button(action: { selectedTab = 1 }) {
                        Text("Scan Now")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    
                    // Core Features Carousel
                    SectionHeader(title: "Core Features")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(coreFeatures) { feature in
                                QuarantineCard {
                                    FeatureCard(feature: feature) {
                                        handleFeatureTap(feature)
                                    }
                                    .frame(height: 130)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    // Security & Tools Carousel
                    SectionHeader(title: "Security & Tools")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(securityAndTools) { feature in
                                QuarantineCard {
                                    FeatureCard(feature: feature) {
                                        handleFeatureTap(feature)
                                    }
                                    .frame(height: 130)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    // Performance Chart Card
                    SectionHeader(title: "Performance")
                    QuarantineCard {
                        Chart {
                            LineMark(x: .value("Metric", "Battery"), y: .value("Usage", battery))
                                .foregroundStyle(Color.blue)
                                .symbol(Circle())
                            LineMark(x: .value("Metric", "CPU"), y: .value("Usage", cpu))
                                .foregroundStyle(Color.blue)
                                .symbol(Circle())
                            LineMark(x: .value("Metric", "Memory"), y: .value("Usage", memory))
                                .foregroundStyle(Color.blue)
                                .symbol(Circle())
                        }
                        .frame(height: 220)
                        .padding()
                    }
                    
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .onAppear {
                loadPerformanceData()
                loadLastScan()
            }
            .navigationDestination(for: String.self) { route in
                if route == "history" { HistoryView() }
                else if route == "logs" { HistoryView() }
                else if route == "breach" { BreachScanView() }
                else if route == "browser" {SecureBrowserView()}

            }
        }
    }
    
    // MARK: - Feature Tap Handler
    private func handleFeatureTap(_ feature: Feature) {
        switch feature.title {
        case "Deep Scan":
            selectedTab = 1
        case "Scan History":
            path.append("history")
        case "Logs":
            path.append("logs")
        case "Breach Scan":
            path.append("breach")
            
        case "Secure Browser":
            path.append("browser")
        default:
            print("\(feature.title) tapped")
        }
    }
    
    // MARK: - Data Loaders
    private func loadPerformanceData() {
        battery = 78
        cpu = 45
        memory = 65
    }
    
    private func loadLastScan() {
        lastScan = "Last scan: Today, 2:45 PM"
        threatsFound = 3
    }
}

// MARK: - Section Header
struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundColor(.primary)
            .padding(.horizontal)
    }
}

// MARK: - Reusable Quarantine-style Card
struct QuarantineCard<Content: View>: View {
    let content: () -> Content
    var body: some View {
        VStack {
            content()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.18), lineWidth: 0.5)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)))
        )
        .padding(.horizontal)
    }
}

// MARK: - Preview
struct DashboardView_Previews: PreviewProvider {
    static var previews: some View {
        DashboardView(selectedTab: .constant(0))
    }
}
