import SwiftUI

@main
struct DeviceLabApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .preferredColorScheme(colorScheme)
                .task {
                    appState.start()
                }
        }
    }

    private var colorScheme: ColorScheme? {
        switch appState.settings.settings.appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "gauge.with.dots.needle.50percent") }
            MonitoringView()
                .tabItem { Label("Monitor", systemImage: "chart.xyaxis.line") }
            DiagnosticsView()
                .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
            BenchmarkView()
                .tabItem { Label("Benchmark", systemImage: "bolt.horizontal.circle") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

#Preview {
    RootView()
        .environment(AppState())
}