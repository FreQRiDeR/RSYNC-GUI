import SwiftUI

@main
struct RSYNC_GUIApp: App {
    
    init() {
        // Disable automatic state restoration
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            // Disable automatic window restoration
            CommandGroup(replacing: .newItem) { }
        }
    }
}
