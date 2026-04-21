//
//  heedApp.swift
//  heed
//
//  Created by Sparsh Shah on 2026-04-08.
//
import AppKit
import SwiftUI

@main
struct heedApp: App {
    private let controller = RecordingController(
        demoMode: ProcessInfo.processInfo.arguments.contains("--heed-ui-test")
    )
    private let isUITestMode = ProcessInfo.processInfo.arguments.contains("--heed-ui-test")

    init() {
        guard isUITestMode else {
            return
        }

        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(controller: controller)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1280, height: 840)
        .windowStyle(.hiddenTitleBar)
    }
}
