import SwiftUI

struct LoftHoursApp: App {
    @StateObject private var config: ConfigStore
    @StateObject private var theme = ThemeStore()
    @StateObject private var controller: SessionController

    init() {
        let cfg = ConfigStore()
        _config = StateObject(wrappedValue: cfg)
        _controller = StateObject(wrappedValue: SessionController(config: cfg))
    }

    var body: some Scene {
        WindowGroup("Loft Hours", id: "main") {
            RootView()
                .environmentObject(controller)
                .environmentObject(theme)
                .environmentObject(config)
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
