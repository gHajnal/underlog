import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            Tab("Dives", systemImage: "list.bullet.rectangle") {
                DiveListView()
            }
            Tab("Statistics", systemImage: "chart.bar.xaxis") {
                StatisticsView()
            }
            Tab("Gas tools", systemImage: "function") {
                GasToolsView()
            }
            Tab("Settings", systemImage: "gearshape") {
                SettingsView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}
