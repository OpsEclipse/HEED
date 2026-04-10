import SwiftUI

struct ContentView: View {
    @StateObject private var controller: RecordingController

    init(controller: RecordingController) {
        _controller = StateObject(wrappedValue: controller)
    }

    var body: some View {
        WorkspaceShell(controller: controller)
            .background(HeedTheme.ColorToken.canvas)
    }
}

#Preview {
    ContentView(controller: RecordingController(demoMode: true))
}
