import AppKit
import Combine
import SwiftUI

struct WorkspaceShell: View {
    @ObservedObject var controller: RecordingController
    @ObservedObject var taskAnalysisController: TaskAnalysisController
    @ObservedObject var taskContextController: TaskContextController
    @ObservedObject var apiKeySettingsViewModel: APIKeySettingsViewModel
    @State private var isSidebarVisible = false
    @State private var isAPIKeySettingsPresented = false
    @StateObject private var windowController = WorkspaceWindowController()

    private var displayedSession: TranscriptSession? {
        controller.activeSession ?? controller.selectedSession
    }

    private var displayedSegments: [TranscriptSegment] {
        displayedSession?.segments ?? []
    }

    var body: some View {
        GeometryReader { _ in
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
                        HStack(alignment: .top, spacing: 0) {
                            ZStack(alignment: .topLeading) {
                                HeedTheme.ColorToken.canvas
                                    .ignoresSafeArea()

                                TranscriptCanvasView(
                                    state: controller.state,
                                    session: displayedSession,
                                    segments: displayedSegments,
                                    sourceJumpRequest: taskAnalysisController.sourceJumpRequest,
                                    highlightedSegmentID: taskAnalysisController.highlightedSegmentID,
                                    appendixFocusNonce: taskAnalysisController.sectionFocusNonce,
                                    autoScrollEnabled: $controller.autoScrollEnabled
                                ) {
                                    TaskAnalysisSectionView(
                                        controller: taskAnalysisController,
                                        taskContextController: taskContextController,
                                        displayedSession: displayedSession
                                    )
                                    .padding(.top, displayedSegments.isEmpty ? 6 : 16)
                                }

                                SidebarToggleButton(isSidebarVisible: $isSidebarVisible)
                                    .padding(.top, 20)
                                    .padding(.leading, 20)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                            if isTaskContextPanelVisible {
                                TaskContextPanelView(
                                    presentation: TaskContextPanelPresentation(state: taskContextController.panelState),
                                    onPrimaryAction: handleTaskContextPrimaryAction,
                                    onSecondaryAction: handleTaskContextSecondaryAction,
                                    onClose: taskContextController.reset
                                )
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                UtilityRailView(
                    primaryStatus: controller.state.statusText,
                    secondaryStatus: utilitySecondaryStatus,
                    details: utilityDetails,
                    actions: utilityActions
                ) {
                    FloatingTransportView(
                        recordingState: controller.state,
                        isEnabled: controller.canRecord,
                        onPrimaryAction: controller.handlePrimaryAction
                    )
                }
            }
            .animation(.easeOut(duration: 0.22), value: isSidebarVisible)
            .heedHiddenWindowScrollBars()
            .background(HeedTheme.ColorToken.canvas.ignoresSafeArea())
            .background {
                WindowAccessView { window in
                    windowController.bind(to: window)
                }
            }
            .onAppear {
                taskAnalysisController.updateDisplayedSession(displayedSession)
            }
            .onChange(of: displayedSession?.id) {
                taskAnalysisController.updateDisplayedSession(displayedSession)
                taskContextController.reset()
            }
            .onChange(of: displayedSession?.segments.count) {
                taskAnalysisController.updateDisplayedSession(displayedSession)
            }
            .onChange(of: displayedSession?.status) {
                taskAnalysisController.updateDisplayedSession(displayedSession)
            }
            .sheet(isPresented: $isAPIKeySettingsPresented) {
                APIKeySettingsView(viewModel: apiKeySettingsViewModel) {
                    isAPIKeySettingsPresented = false
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
        var actions: [UtilityRailView.Action] = []

        if let compileActionTitle = taskAnalysisController.compileActionTitle,
           taskAnalysisController.canShowCompileAction {
            actions.append(
                .init(
                    id: "compile",
                    title: compileActionTitle,
                    isEnabled: taskAnalysisController.isCompileActionEnabled,
                    accessibilityIdentifier: "compile-tasks"
                ) {
                    taskContextController.reset()
                    taskAnalysisController.handleCompileAction()
                }
            )
        }

        actions.append(
            .init(
                id: "set-api-key",
                title: "Set API key",
                accessibilityIdentifier: "set-api-key"
            ) {
                isAPIKeySettingsPresented = true
            }
        )

        actions.append(
            .init(
                id: "copy",
                title: "Copy as text",
                isEnabled: displayedSession != nil,
                accessibilityIdentifier: "copy-as-text"
            ) {
                controller.copySelectedSession()
            }
        )

        actions.append(
            .init(
                id: "fullscreen",
                title: windowController.isFullScreen ? "Exit full screen" : "Full screen",
                accessibilityIdentifier: "fullscreen-toggle"
            ) {
                windowController.toggleFullScreen()
            }
        )

        return actions
    }

    private var isTaskContextPanelVisible: Bool {
        if case .idle = taskContextController.panelState {
            return false
        }

        return true
    }

    private func handleTaskContextPrimaryAction() {
        guard let taskID = taskContextController.selectedTaskID else {
            return
        }

        taskAnalysisController.requestSpawnAgent(for: taskID)
    }

    private func handleTaskContextSecondaryAction() {
        guard let displayedSession, let selectedTask = taskContextController.selectedTask else {
            return
        }

        taskContextController.prepareTaskContext(for: selectedTask, in: displayedSession)
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

        updateFullScreenState(window.styleMask.contains(.fullScreen))
    }

    func toggleFullScreen() {
        window?.toggleFullScreen(nil)
    }

    private func updateFullScreenState(_ newValue: Bool) {
        guard isFullScreen != newValue else {
            return
        }

        isFullScreen = newValue
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
                self?.updateFullScreenState(true)
            }
        }

        exitFullScreenObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didExitFullScreenNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateFullScreenState(false)
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
        .accessibilityIdentifier("sidebar-toggle")
    }
}
