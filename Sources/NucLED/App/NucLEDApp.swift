import SwiftUI

@main
struct NucLEDApp: App {
    @NSApplicationDelegateAdaptor(NucLEDAppDelegate.self) private var appDelegate

    var body: some Scene {
        // The app's visible interface is owned by the explicit AppKit status
        // item and popover created by the delegate. Keep a Settings scene so
        // SwiftUI retains a normal application lifecycle without creating a
        // Dock window.
        Settings {
            EmptyView()
        }
    }
}
