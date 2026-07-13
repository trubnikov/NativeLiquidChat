import SwiftUI

@main
struct NativeLiquidChatApp: App {
    @AppStorage("appTheme") private var appThemeRaw = AppTheme.system.rawValue

    private var theme: AppTheme {
        AppTheme(rawValue: appThemeRaw) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(theme.colorScheme)
                .tint(DS.accent)
        }
    }
}
