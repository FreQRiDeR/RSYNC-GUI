//
//  RSYNC_GUIApp.swift
//  RSYNC-GUI
//
//  Created by terraMODA on 9/15/25.
//

import SwiftUI

@main
struct RSYNC_GUIApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
