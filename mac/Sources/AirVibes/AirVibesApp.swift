import AppKit
import SwiftUI

@main
struct AirVibesApp: App {
    @StateObject private var model = AppModel()

    init() {
        // Menu bar only, no Dock icon (also set by LSUIElement when run as a bundled .app).
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView().environmentObject(model)
        } label: {
            Text(model.menuTitle)
        }
        .menuBarExtraStyle(.window)
    }
}
