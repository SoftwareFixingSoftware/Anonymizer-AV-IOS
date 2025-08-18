//
//  MainTabView.swift
//  Anonymizer AV
//

import SwiftUI

struct MainTabView: View {
    @StateObject private var session = SessionManager.shared
    @State private var selectedTab: Int = 0 // Track active tab

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(selectedTab: $selectedTab)
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)

            ScanOptionsView()
                .tabItem {
                    Label("Scan", systemImage: "magnifyingglass.circle.fill")
                }
                .tag(1)

            QuarantineView()
                .tabItem {
                    Label("Quarantine", systemImage: "tray.full.fill")
                }
                .tag(2)

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.fill")
                }
                .tag(3)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(4)
        }
        .accentColor(.accentCyan)
    }
}

 
private struct HistoryPlaceholderView: View {
    var body: some View {
        VStack { Text("History").font(.title) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground.ignoresSafeArea())
    }
}

 
