import AppKit
import Combine
import SwiftUI

enum ShellMode: Equatable {
    case terminal
    case newSession
}

struct WorkspaceShell: View {
    @ObservedObject var controller: RecordingController
    @ObservedObject var taskAnalysisController: TaskAnalysisController
    @ObservedObject var taskPrepController: TaskPrepController
    @ObservedObject var apiKeySettingsViewModel: APIKeySettingsViewModel
    @State private var isSidebarVisible = true
    @State private var isAPIKeySettingsPresented = false
    @State private var searchText = ""
    @State private var terminalWorkspace = TerminalShellWorkspace.preview
    @State private var selectedShellMode: ShellMode = .terminal
    @StateObject private var windowController = WorkspaceWindowController()

    private var displayedSession: TranscriptSession? {
        controller.activeSession ?? controller.selectedSession
    }

    private var displayedMicSegments: [TranscriptSegment] {
        displayedSession?.micSegments ?? []
    }

    private var displayedSystemSegments: [TranscriptSegment] {
        displayedSession?.systemSegments ?? []
    }

    var isTaskPrepWorkspaceVisible: Bool {
        taskPrepController.activeTaskID != nil
    }

    var body: some View {
        GeometryReader { _ in
            VStack(spacing: 0) {
                TopNavView(
                    isSidebarVisible: $isSidebarVisible,
                    searchText: $searchText
                ) {
                    isAPIKeySettingsPresented = true
                }

                HStack(spacing: 0) {
                    if isSidebarVisible {
                        ProjectBranchSidebarView(
                            workspace: terminalWorkspace,
                            onTasks: {
                                selectTasksTab()
                            },
                            onNewSession: {
                                selectedShellMode = .newSession
                            },
                            onSelectBranch: selectBranch,
                            onSelectTab: selectTab
                        )
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    }

                    ZStack(alignment: .topLeading) {
                        HStack(alignment: .top, spacing: 0) {
                            mainWorkspace
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                UtilityRailView(
                    primaryStatus: utilityPrimaryStatus,
                    secondaryStatus: utilitySecondaryStatus,
                    details: utilityDetails,
                    leadingActions: leadingUtilityActions,
                    trailingActions: trailingUtilityActions
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
                taskPrepController.reset()
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

    private var mainWorkspace: some View {
        ZStack(alignment: .topLeading) {
            HeedTheme.ColorToken.canvas
                .ignoresSafeArea()

            Group {
                switch selectedShellMode {
                case .terminal:
                    temporaryTerminalWorkspace
                case .newSession:
                    transcriptWorkspace
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var temporaryTerminalWorkspace: some View {
        let project = terminalWorkspace.selectedProject
        let branch = terminalWorkspace.selectedBranch
        let tab = terminalWorkspace.selectedBranchTab
        let terminal = terminalWorkspace.selectedTerminal

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(project?.name ?? "no project")
                Text("/")
                    .foregroundStyle(HeedTheme.ColorToken.textSecondary)
                Text(branch?.name ?? "no branch")
                Text("/")
                    .foregroundStyle(HeedTheme.ColorToken.textSecondary)
                Text(tab?.title ?? "no tab")
            }
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(HeedTheme.ColorToken.textPrimary)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 42)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(HeedTheme.ColorToken.borderStrong)
                    .frame(height: HeedTheme.Stroke.brutalist)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array((terminal?.promptLines ?? []).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(line.hasPrefix("$") ? HeedTheme.ColorToken.textSecondary : HeedTheme.ColorToken.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if terminal == nil {
                        Text("No terminal selected")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(HeedTheme.ColorToken.textSecondary)
                    }
                }
                .padding(18)
            }
            .heedHiddenScrollBars()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(HeedTheme.ColorToken.canvas)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("temporary-terminal-workspace")
    }

    private var transcriptWorkspace: some View {
        Group {
            if isTaskPrepWorkspaceVisible {
                TaskPrepWorkspaceView(
                    controller: taskPrepController,
                    onClose: taskPrepController.reset
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                TranscriptCanvasView(
                    state: controller.state,
                    session: displayedSession,
                    micSegments: displayedMicSegments,
                    systemSegments: displayedSystemSegments,
                    sourceProcessingStates: controller.sourceProcessingStates,
                    sourceJumpRequest: taskAnalysisController.sourceJumpRequest,
                    highlightedSegmentID: taskAnalysisController.highlightedSegmentID,
                    appendixFocusNonce: taskAnalysisController.sectionFocusNonce,
                    autoScrollEnabled: $controller.autoScrollEnabled
                ) {
                    TaskAnalysisSectionView(
                        controller: taskAnalysisController,
                        taskPrepController: taskPrepController,
                        displayedSession: displayedSession
                    )
                    .padding(.top, displayedSession?.segments.isEmpty == false ? 16 : 6)
                }
                .transition(.opacity)
            }
        }
    }

    private func selectBranch(_ project: TerminalShellProject, _ branch: TerminalShellBranch) {
        terminalWorkspace.selectedProjectID = project.id
        terminalWorkspace.selectedBranchID = branch.id
        selectDefaultTab(in: branch)
        selectDefaultChangedFile(in: branch)
        selectedShellMode = .terminal
    }

    private func selectTab(
        _ project: TerminalShellProject,
        _ branch: TerminalShellBranch,
        _ tab: TerminalShellBranchTab
    ) {
        terminalWorkspace.selectedProjectID = project.id
        terminalWorkspace.selectedBranchID = branch.id
        terminalWorkspace.selectedBranchTabID = tab.id
        selectedShellMode = .terminal

        switch tab.kind {
        case .terminal:
            terminalWorkspace.selectedTerminalID = tab.id
        case .changes:
            selectDefaultChangedFile(in: branch)
            break
        case .taskPrep, .tasks:
            break
        }
    }

    private func selectTasksTab() {
        guard let branch = terminalWorkspace.selectedBranch,
              let tasksTab = branch.tabs.first(where: { $0.kind == .tasks }) else {
            selectedShellMode = .terminal
            return
        }

        terminalWorkspace.selectedBranchTabID = tasksTab.id
        selectedShellMode = .terminal
    }

    private func selectDefaultTab(in branch: TerminalShellBranch) {
        let defaultTab = branch.tabs.first { $0.kind == .terminal } ?? branch.tabs.first

        terminalWorkspace.selectedBranchTabID = defaultTab?.id ?? ""

        if defaultTab?.kind == .terminal {
            terminalWorkspace.selectedTerminalID = defaultTab?.id ?? ""
        } else {
            terminalWorkspace.selectedTerminalID = branch.terminals.first?.id ?? ""
        }
    }

    private func selectDefaultChangedFile(in branch: TerminalShellBranch) {
        guard let firstChangedFile = branch.changedFiles.first else {
            terminalWorkspace.selectedChangedFileID = ""
            return
        }

        terminalWorkspace.selectedChangedFileID = firstChangedFile.id
    }

    var utilityPrimaryStatus: String? {
        controller.state.statusText
    }

    var utilitySecondaryStatus: String? {
        switch controller.state {
        case .recording, .stopping, .processing:
            return controller.elapsedTime.heedClockString
        case .idle, .requestingPermissions, .ready, .error:
            return nil
        }
    }

    var utilityDetails: [UtilityRailView.Detail] {
        if controller.state == .processing {
            return AudioSource.allCases.map { source in
                UtilityRailView.Detail(
                    id: source.rawValue,
                    label: source.label,
                    value: controller.sourceProcessingStates[source]?.rawValue ?? SourceProcessingState.queued.rawValue
                )
            }
        }

        return []
    }

    var leadingUtilityActions: [UtilityRailView.Action] {
        []
    }

    var trailingUtilityActions: [UtilityRailView.Action] {
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
                    taskPrepController.reset()
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
                title: "Copy text",
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
