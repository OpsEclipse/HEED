import AppKit
import Combine
import SwiftUI

struct WorkspaceShell: View {
    @ObservedObject var controller: RecordingController
    @State private var isSidebarVisible = false
    @StateObject private var windowController = WorkspaceWindowController()

    private var displayedSession: TranscriptSession? {
        controller.activeSession ?? controller.selectedSession
    }

    private var displayedSegments: [TranscriptSegment] {
        displayedSession?.segments ?? []
    }

    var body: some View {
        GeometryReader { geometry in
            let compactWidth = geometry.size.width < 820

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    if isSidebarVisible {
                        SessionSidebarView(
                            sessions: controller.sessions,
                            selectedSessionID: controller.selectedSessionID,
                            activeSessionID: controller.activeSession?.id,
                            onSelect: { sessionID in
                                controller.selectSession(sessionID)
                            }
                        )
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    }

                    ZStack(alignment: .topLeading) {
                        HeedTheme.ColorToken.canvas
                            .ignoresSafeArea()

                        TranscriptCanvasView(
                            state: controller.state,
                            session: displayedSession,
                            segments: displayedSegments,
                            autoScrollEnabled: $controller.autoScrollEnabled
                        )

                        SidebarToggleButton(isSidebarVisible: $isSidebarVisible)
                            .padding(.top, 20)
                            .padding(.leading, 20)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                UtilityRailView(
                    primaryStatus: controller.state.statusText,
                    secondaryStatus: utilitySecondaryStatus,
                    details: utilityDetails,
                    actions: utilityActions
                )
            }
            .animation(.easeOut(duration: 0.22), value: isSidebarVisible)
            .background(HeedTheme.ColorToken.canvas.ignoresSafeArea())
            .overlay(alignment: compactWidth ? .topTrailing : .bottom) {
                FloatingTransportView(
                    recordingState: controller.state,
                    isEnabled: controller.canRecord,
                    onPrimaryAction: controller.handlePrimaryAction
                )
                .padding(compactWidth ? .top : .bottom, compactWidth ? 20 : 78)
                .padding(.trailing, compactWidth ? 20 : 0)
            }
            .background {
                WindowAccessView { window in
                    windowController.bind(to: window)
                }
            }
        }
    }

    private var utilitySecondaryStatus: String? {
        if controller.state == .recording || controller.state == .stopping {
            return controller.elapsedTime.heedClockString
        }

        return displayedSession?.duration.heedClockString
    }

    private var utilityDetails: [UtilityRailView.Detail] {
        [
            .init(label: "Mode", value: "Mic + system"),
            .init(label: "Auto-scroll", value: controller.autoScrollEnabled ? "On" : "Off")
        ]
    }

    private var utilityActions: [UtilityRailView.Action] {
        [
            .init(
                id: "copy",
                title: "Copy as text",
                isEnabled: displayedSession != nil,
                accessibilityIdentifier: "copy-as-text"
            ) {
                controller.copySelectedSession()
            },
            .init(
                id: "fullscreen",
                title: windowController.isFullScreen ? "Exit full screen" : "Full screen",
                accessibilityIdentifier: "fullscreen-toggle"
            ) {
                windowController.toggleFullScreen()
            }
        ]
    }
}

@MainActor
private final class WorkspaceWindowController: ObservableObject {
    @Published private(set) var isFullScreen = false

    private weak var window: NSWindow?
    private var enterFullScreenObserver: NSObjectProtocol?
    private var exitFullScreenObserver: NSObjectProtocol?

    deinit {
        if let enterFullScreenObserver {
            NotificationCenter.default.removeObserver(enterFullScreenObserver)
        }
        if let exitFullScreenObserver {
            NotificationCenter.default.removeObserver(exitFullScreenObserver)
        }
    }

    func bind(to window: NSWindow) {
        if self.window !== window {
            self.window = window
            configure(window)
            installObservers(for: window)
        }

        isFullScreen = window.styleMask.contains(.fullScreen)
    }

    func toggleFullScreen() {
        window?.toggleFullScreen(nil)
    }

    private func configure(_ window: NSWindow) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.toolbar = nil
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
    }

    private func installObservers(for window: NSWindow) {
        if let enterFullScreenObserver {
            NotificationCenter.default.removeObserver(enterFullScreenObserver)
        }
        if let exitFullScreenObserver {
            NotificationCenter.default.removeObserver(exitFullScreenObserver)
        }

        enterFullScreenObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didEnterFullScreenNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isFullScreen = true
            }
        }

        exitFullScreenObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didExitFullScreenNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isFullScreen = false
            }
        }
    }
}

private struct SidebarToggleButton: View {
    @Binding var isSidebarVisible: Bool

    var body: some View {
        Button(isSidebarVisible ? "Close" : "Sessions") {
            withAnimation(.easeOut(duration: 0.22)) {
                isSidebarVisible.toggle()
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .foregroundStyle(HeedTheme.ColorToken.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(HeedTheme.ColorToken.canvas.opacity(0.9))
        .accessibilityIdentifier("sidebar-toggle")
    }
}
