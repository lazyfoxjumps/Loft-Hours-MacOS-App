import SwiftUI

struct LoftHoursApp: App {
    @StateObject private var config: ConfigStore
    @StateObject private var theme = ThemeStore()
    @StateObject private var controller: SessionController
    @StateObject private var googleAuth: GoogleAuth

    init() {
        let cfg = ConfigStore()
        let auth = GoogleAuth()
        _config = StateObject(wrappedValue: cfg)
        _googleAuth = StateObject(wrappedValue: auth)
        _controller = StateObject(wrappedValue: SessionController(config: cfg, auth: auth))
    }

    var body: some Scene {
        WindowGroup("Loft Hours", id: "main") {
            RootView()
                .environmentObject(controller)
                .environmentObject(theme)
                .environmentObject(config)
                .environmentObject(googleAuth)
        }
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuBarView()
                .environmentObject(controller)
        } label: {
            if let icon = AppImages.menuBar {
                Image(nsImage: icon)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: "timer")
            }
        }
    }
}
