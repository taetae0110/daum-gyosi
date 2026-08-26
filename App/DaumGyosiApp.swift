import SwiftUI

@main
struct DaumGyosiApp: App {
    @ObservedObject private var store = SettingsStore.shared

    var body: some Scene {
        WindowGroup {
            if store.settings == nil {
                OnboardingView()
            } else {
                TodayView()
            }
        }
    }
}
