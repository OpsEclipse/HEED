//
//  heedApp.swift
//  heed
//
//  Created by Sparsh Shah on 2026-04-08.
//

import SwiftUI

@main
struct heedApp: App {
    private let controller = RecordingController(
        demoMode: ProcessInfo.processInfo.arguments.contains("--heed-ui-test")
    )

    var body: some Scene {
        WindowGroup {
            ContentView(controller: controller)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1280, height: 840)
        .windowStyle(.hiddenTitleBar)
    }
}
