# Brutalist Terminal Shell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the approved brutalist, terminal-first Heed shell while keeping recording, transcript review, task compile, and task prep reachable.

**Architecture:** Add a small fixture-backed workspace model [temporary data used to build the UI before real Git integration]. Compose the shell from focused SwiftUI views under `heed/UI`. Keep capture, transcription, persistence, and task-prep controllers outside the new view files.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing, XCTest UI tests, macOS 14 target.

---

## File Structure

- Create `heed/UI/TerminalShellModels.swift`
  - Owns project, branch, branch tab, terminal tab, and changed-file fixture state.
- Create `heed/UI/TopNavView.swift`
  - Owns the top brutalist nav bar.
- Create `heed/UI/ProjectBranchSidebarView.swift`
  - Owns `tasks`, `new session`, projects, branches, and nested branch tabs.
- Create `heed/UI/TerminalWorkspaceView.swift`
  - Owns center terminal tabs and terminal display.
- Create `heed/UI/ChangedFilesPane.swift`
  - Owns the right changed-files pane.
- Modify `heed/UI/HeedTheme.swift`
  - Adds brutalist color, opacity, corner, and stroke tokens.
- Modify `heed/UI/WorkspaceShell.swift`
  - Wires the new shell around existing controllers.
- Modify `heedTests/WorkspaceShellTests.swift`
  - Adds model and shell state tests.
- Modify `heedUITests/heedUITests.swift`
  - Updates launch expectations and keeps recording and prep flows covered.
- Modify `docs/FRONTEND.md`
  - Records the new UI reality after implementation.
- Modify `README.md`
  - Updates the current UI summary after implementation.

## Task 1: Add Terminal Shell Models

**Files:**
- Create: `heed/UI/TerminalShellModels.swift`
- Modify: `heedTests/WorkspaceShellTests.swift`

- [ ] **Step 1: Write the failing model tests**

Add these tests to `heedTests/WorkspaceShellTests.swift`:

```swift
@Test func terminalShellFixtureDefaultsToSelectedBranchAndTerminal() {
    let state = TerminalShellWorkspace.preview

    #expect(state.selectedProject?.name == "heed")
    #expect(state.selectedBranch?.name == "ui-revamp")
    #expect(state.selectedBranchTab?.kind == .terminal)
    #expect(state.selectedTerminal?.title == "terminal 1")
}

@Test func terminalShellFixtureExposesBranchScopedTabs() {
    let state = TerminalShellWorkspace.preview

    #expect(state.selectedBranch?.tabs.map(\.title) == [
        "terminal 1",
        "terminal 2",
        "unstaged changes",
        "task prep",
        "tasks"
    ])
}

@Test func terminalShellFixtureExposesChangedFileSummaries() {
    let state = TerminalShellWorkspace.preview

    #expect(state.changedFiles.map(\.path) == [
        "heed/UI/WorkspaceShell.swift",
        "heed/UI/ProjectBranchSidebarView.swift",
        "heed/UI/TerminalWorkspaceView.swift"
    ])
    #expect(state.selectedChangedFile?.summaryLines.contains("+ terminal tab strip") == true)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' -only-testing:heedTests/WorkspaceShellTests test
```

Expected: FAIL because `TerminalShellWorkspace` is not defined.

- [ ] **Step 3: Add the model implementation**

Create `heed/UI/TerminalShellModels.swift`:

```swift
import Foundation

struct TerminalShellWorkspace: Equatable {
    var projects: [TerminalShellProject]
    var selectedProjectID: String
    var selectedBranchID: String
    var selectedBranchTabID: String
    var selectedTerminalID: String
    var selectedChangedFileID: String

    var selectedProject: TerminalShellProject? {
        projects.first { $0.id == selectedProjectID }
    }

    var selectedBranch: TerminalShellBranch? {
        selectedProject?.branches.first { $0.id == selectedBranchID }
    }

    var selectedBranchTab: TerminalShellBranchTab? {
        selectedBranch?.tabs.first { $0.id == selectedBranchTabID }
    }

    var selectedTerminal: TerminalShellTerminal? {
        selectedBranch?.terminals.first { $0.id == selectedTerminalID }
    }

    var changedFiles: [TerminalShellChangedFile] {
        selectedBranch?.changedFiles ?? []
    }

    var selectedChangedFile: TerminalShellChangedFile? {
        changedFiles.first { $0.id == selectedChangedFileID }
    }

    static let preview = TerminalShellWorkspace(
        projects: [
            TerminalShellProject(
                id: "heed",
                name: "heed",
                branches: [
                    TerminalShellBranch(
                        id: "heed-main",
                        name: "main",
                        tabs: [
                            .init(id: "heed-main-terminal-1", title: "terminal 1", kind: .terminal),
                            .init(id: "heed-main-changes", title: "changes", kind: .changes),
                            .init(id: "heed-main-tasks", title: "tasks", kind: .tasks)
                        ],
                        terminals: [
                            .init(
                                id: "heed-main-terminal-1",
                                title: "terminal 1",
                                promptLines: [
                                    "$ git status --short",
                                    "clean working tree"
                                ]
                            )
                        ],
                        changedFiles: []
                    ),
                    TerminalShellBranch(
                        id: "heed-ui-revamp",
                        name: "ui-revamp",
                        tabs: [
                            .init(id: "heed-ui-revamp-terminal-1", title: "terminal 1", kind: .terminal),
                            .init(id: "heed-ui-revamp-terminal-2", title: "terminal 2", kind: .terminal),
                            .init(id: "heed-ui-revamp-changes", title: "unstaged changes", kind: .changes),
                            .init(id: "heed-ui-revamp-task-prep", title: "task prep", kind: .taskPrep),
                            .init(id: "heed-ui-revamp-tasks", title: "tasks", kind: .tasks)
                        ],
                        terminals: [
                            .init(
                                id: "heed-ui-revamp-terminal-1",
                                title: "terminal 1",
                                promptLines: [
                                    "$ cd ~/Documents/projects/xcode/heed",
                                    "$ git status --short",
                                    "M  heed/UI/WorkspaceShell.swift",
                                    "M  heed/UI/ProjectBranchSidebarView.swift",
                                    "A  heed/UI/TerminalWorkspaceView.swift",
                                    "$ codex",
                                    "Ready in branch context: ui-revamp"
                                ]
                            ),
                            .init(
                                id: "heed-ui-revamp-terminal-2",
                                title: "terminal 2",
                                promptLines: [
                                    "$ xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' build",
                                    "Build ready"
                                ]
                            )
                        ],
                        changedFiles: [
                            .init(
                                id: "workspace-shell",
                                status: "M",
                                path: "heed/UI/WorkspaceShell.swift",
                                summaryLines: [
                                    "+ terminal tab strip",
                                    "+ branch-scoped side tabs",
                                    "- transcript-first center"
                                ]
                            ),
                            .init(
                                id: "project-sidebar",
                                status: "M",
                                path: "heed/UI/ProjectBranchSidebarView.swift",
                                summaryLines: [
                                    "+ project branch tree",
                                    "+ nested branch tabs",
                                    "+ selected branch accent"
                                ]
                            ),
                            .init(
                                id: "terminal-workspace",
                                status: "A",
                                path: "heed/UI/TerminalWorkspaceView.swift",
                                summaryLines: [
                                    "+ tabbed terminal surface",
                                    "+ brutalist terminal body",
                                    "+ branch context title"
                                ]
                            )
                        ]
                    )
                ]
            ),
            TerminalShellProject(
                id: "website",
                name: "website",
                branches: [
                    TerminalShellBranch(
                        id: "website-feature-auth",
                        name: "feature/auth",
                        tabs: [
                            .init(id: "website-feature-auth-terminal-1", title: "terminal 1", kind: .terminal),
                            .init(id: "website-feature-auth-changes", title: "changes", kind: .changes)
                        ],
                        terminals: [
                            .init(
                                id: "website-feature-auth-terminal-1",
                                title: "terminal 1",
                                promptLines: [
                                    "$ pnpm test",
                                    "Ready in branch context: feature/auth"
                                ]
                            )
                        ],
                        changedFiles: [
                            .init(
                                id: "auth-page",
                                status: "M",
                                path: "app/auth/page.tsx",
                                summaryLines: [
                                    "+ tighter form layout",
                                    "+ clearer loading state"
                                ]
                            )
                        ]
                    )
                ]
            )
        ],
        selectedProjectID: "heed",
        selectedBranchID: "heed-ui-revamp",
        selectedBranchTabID: "heed-ui-revamp-terminal-1",
        selectedTerminalID: "heed-ui-revamp-terminal-1",
        selectedChangedFileID: "workspace-shell"
    )
}

struct TerminalShellProject: Equatable, Identifiable {
    let id: String
    let name: String
    let branches: [TerminalShellBranch]
}

struct TerminalShellBranch: Equatable, Identifiable {
    let id: String
    let name: String
    let tabs: [TerminalShellBranchTab]
    let terminals: [TerminalShellTerminal]
    let changedFiles: [TerminalShellChangedFile]
}

struct TerminalShellBranchTab: Equatable, Identifiable {
    let id: String
    let title: String
    let kind: TerminalShellBranchTabKind
}

enum TerminalShellBranchTabKind: Equatable {
    case terminal
    case changes
    case taskPrep
    case tasks
}

struct TerminalShellTerminal: Equatable, Identifiable {
    let id: String
    let title: String
    let promptLines: [String]
}

struct TerminalShellChangedFile: Equatable, Identifiable {
    let id: String
    let status: String
    let path: String
    let summaryLines: [String]
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:

```bash
xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' -only-testing:heedTests/WorkspaceShellTests test
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add heed/UI/TerminalShellModels.swift heedTests/WorkspaceShellTests.swift
git commit -m "feat: add terminal shell workspace model"
```

## Task 2: Add Brutalist Theme Tokens

**Files:**
- Modify: `heed/UI/HeedTheme.swift`
- Modify: `heedTests/WorkspaceShellTests.swift`

- [ ] **Step 1: Write the failing theme token test**

Add this test to `heedTests/WorkspaceShellTests.swift`:

```swift
@Test func brutalistThemeTokensStaySharpAndHighContrast() {
    #expect(HeedTheme.Opacity.brutalistBorder == 0.6)
    #expect(HeedTheme.Opacity.brutalistDivider == 0.3)
    #expect(HeedTheme.Corner.brutalist == 0)
    #expect(HeedTheme.Stroke.brutalist == 1)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' -only-testing:heedTests/WorkspaceShellTests test
```

Expected: FAIL because the brutalist tokens do not exist.

- [ ] **Step 3: Add theme tokens**

Modify `heed/UI/HeedTheme.swift`:

```swift
enum HeedTheme {
    enum ColorToken {
        static let canvas = Color.black
        static let panel = Color.black
        static let panelRaised = Color(red: 0.04, green: 0.04, blue: 0.04)
        static let textPrimary = Color.white
        static let textSecondary = Color.white.opacity(0.58)
        static let borderSubtle = Color.white.opacity(Opacity.brutalistDivider)
        static let borderStrong = Color.white.opacity(Opacity.brutalistBorder)
        static let shadow = Color.black.opacity(0.38)
        static let recording = Color(red: 0.88, green: 0.15, blue: 0.18)
        static let warning = Color(red: 0.73, green: 0.54, blue: 0.20)
        static let success = Color(red: 0.38, green: 0.72, blue: 0.46)
        static let actionYellow = Color(red: 0.72, green: 0.91, blue: 0.20)
    }

    enum Opacity {
        static let brutalistBorder: Double = 0.6
        static let brutalistDivider: Double = 0.3
        static let disabled: Double = 0.32
    }

    enum Corner {
        static let brutalist: CGFloat = 0
        static let pill: CGFloat = 999
        static let panel: CGFloat = 8
        static let button: CGFloat = 0
    }

    enum Stroke {
        static let hairline: CGFloat = 1
        static let emphasis: CGFloat = 1.5
        static let brutalist: CGFloat = 1
    }
}
```

Keep existing `Space`, `Layout`, `Typography`, and `Motion` definitions below this block. If a duplicate enum exists, merge the new constants into the existing enum instead of creating a second enum with the same name.

- [ ] **Step 4: Run the tests to verify they pass**

Run:

```bash
xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' -only-testing:heedTests/WorkspaceShellTests test
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add heed/UI/HeedTheme.swift heedTests/WorkspaceShellTests.swift
git commit -m "style: add brutalist theme tokens"
```

## Task 3: Build Top Nav

**Files:**
- Create: `heed/UI/TopNavView.swift`
- Modify: `heedUITests/heedUITests.swift`
- Modify: `heed/UI/WorkspaceShell.swift`

- [ ] **Step 1: Write the failing UI test**

In `testRecordingShellLoadsInUITestMode`, replace the first launch assertions with:

```swift
XCTAssertTrue(app.otherElements["top-nav"].waitForExistence(timeout: uiTimeout))
XCTAssertTrue(app.buttons["sidebar-toggle"].exists)
XCTAssertTrue(app.textFields["shell-search"].exists)
XCTAssertTrue(app.buttons["open-ide-menu"].exists)
XCTAssertTrue(app.buttons["settings-button"].exists)
```

- [ ] **Step 2: Run the UI test to verify it fails**

Run:

```bash
xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' -only-testing:heedUITests/heedUITests/testRecordingShellLoadsInUITestMode test
```

Expected: FAIL because `top-nav`, `shell-search`, `open-ide-menu`, and `settings-button` do not exist.

- [ ] **Step 3: Create `TopNavView`**

Create `heed/UI/TopNavView.swift`:

```swift
import SwiftUI

struct TopNavView: View {
    @Binding var isSidebarVisible: Bool
    @Binding var searchText: String
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.16)) {
                    isSidebarVisible.toggle()
                }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 48, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(HeedTheme.ColorToken.textPrimary)
            .accessibilityIdentifier("sidebar-toggle")

            Rectangle()
                .fill(HeedTheme.ColorToken.borderStrong)
                .frame(width: HeedTheme.Stroke.brutalist)

            TextField("search tasks, projects, branches, files", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(HeedTheme.ColorToken.textPrimary)
                .padding(.horizontal, 12)
                .frame(maxWidth: 560)
                .frame(height: 24)
                .overlay {
                    Rectangle()
                        .stroke(HeedTheme.ColorToken.borderStrong, lineWidth: HeedTheme.Stroke.brutalist)
                }
                .accessibilityIdentifier("shell-search")
                .frame(maxWidth: .infinity)

            Menu {
                Button("Xcode") { }
                Button("Default editor") { }
            } label: {
                Text("OPEN IDE")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .frame(width: 148, height: 44)
            }
            .menuStyle(.borderlessButton)
            .foregroundStyle(HeedTheme.ColorToken.textPrimary)
            .accessibilityIdentifier("open-ide-menu")

            Rectangle()
                .fill(HeedTheme.ColorToken.borderStrong)
                .frame(width: HeedTheme.Stroke.brutalist)

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 48, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(HeedTheme.ColorToken.textPrimary)
            .accessibilityIdentifier("settings-button")
        }
        .frame(height: 44)
        .background(HeedTheme.ColorToken.canvas)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(HeedTheme.ColorToken.borderStrong)
                .frame(height: HeedTheme.Stroke.brutalist)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("top-nav")
    }
}
```

- [ ] **Step 4: Wire `TopNavView` into `WorkspaceShell`**

In `heed/UI/WorkspaceShell.swift`, add:

```swift
@State private var searchText = ""
```

Then put `TopNavView` above the main `HStack`:

```swift
TopNavView(
    isSidebarVisible: $isSidebarVisible,
    searchText: $searchText
) {
    isAPIKeySettingsPresented = true
}
```

Remove the old `SidebarToggleButton` overlay from `mainWorkspace`.

- [ ] **Step 5: Run the UI test to verify it passes**

Run:

```bash
xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' -only-testing:heedUITests/heedUITests/testRecordingShellLoadsInUITestMode test
```

Expected: PASS for the top nav assertions.

- [ ] **Step 6: Commit**

```bash
git add heed/UI/TopNavView.swift heed/UI/WorkspaceShell.swift heedUITests/heedUITests.swift
git commit -m "feat: add brutalist top nav"
```

## Task 4: Build Project And Branch Sidebar

**Files:**
- Create: `heed/UI/ProjectBranchSidebarView.swift`
- Modify: `heed/UI/WorkspaceShell.swift`
- Modify: `heedUITests/heedUITests.swift`

- [ ] **Step 1: Write the failing UI test**

Add these assertions to `testRecordingShellLoadsInUITestMode` after the top nav assertions:

```swift
XCTAssertTrue(app.otherElements["project-branch-sidebar"].exists)
XCTAssertTrue(app.buttons["sidebar-tasks"].exists)
XCTAssertTrue(app.buttons["sidebar-new-session"].exists)
XCTAssertTrue(app.staticTexts["heed"].exists)
XCTAssertTrue(app.buttons["branch-row-heed-ui-revamp"].exists)
XCTAssertTrue(app.buttons["branch-tab-heed-ui-revamp-terminal-1"].exists)
XCTAssertTrue(app.buttons["branch-tab-heed-ui-revamp-changes"].exists)
```

- [ ] **Step 2: Run the UI test to verify it fails**

Run:

```bash
xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' -only-testing:heedUITests/heedUITests/testRecordingShellLoadsInUITestMode test
```

Expected: FAIL because the project branch sidebar does not exist.

- [ ] **Step 3: Create `ProjectBranchSidebarView`**

Create `heed/UI/ProjectBranchSidebarView.swift`:

```swift
import SwiftUI

struct ProjectBranchSidebarView: View {
    let workspace: TerminalShellWorkspace
    let onNewSession: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarAction("tasks", identifier: "sidebar-tasks") { }
            sidebarAction("new session", identifier: "sidebar-new-session", action: onNewSession)

            Rectangle()
                .fill(HeedTheme.ColorToken.borderStrong)
                .frame(height: HeedTheme.Stroke.brutalist)
                .padding(.vertical, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(workspace.projects) { project in
                        projectSection(project)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }
            .heedHiddenScrollBars()
        }
        .frame(width: 250)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(HeedTheme.ColorToken.canvas)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(HeedTheme.ColorToken.borderStrong)
                .frame(width: HeedTheme.Stroke.brutalist)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project-branch-sidebar")
    }

    private func sidebarAction(
        _ title: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(HeedTheme.ColorToken.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private func projectSection(_ project: TerminalShellProject) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(project.name)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(HeedTheme.ColorToken.textPrimary)
                .accessibilityIdentifier("project-row-\(project.id)")

            ForEach(project.branches) { branch in
                branchSection(branch)
            }
        }
    }

    private func branchSection(_ branch: TerminalShellBranch) -> some View {
        let isSelected = branch.id == workspace.selectedBranchID

        return VStack(alignment: .leading, spacing: 2) {
            Button { } label: {
                Text(branch.name)
                    .font(.system(size: 12, weight: isSelected ? .bold : .medium, design: .monospaced))
                    .foregroundStyle(HeedTheme.ColorToken.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 14)
                    .padding(.vertical, 4)
                    .background(isSelected ? Color.white.opacity(0.12) : Color.clear)
                    .overlay(alignment: .leading) {
                        if isSelected {
                            Rectangle()
                                .fill(HeedTheme.ColorToken.textPrimary)
                                .frame(width: 3)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("branch-row-\(branch.id)")

            ForEach(branch.tabs) { tab in
                Button { } label: {
                    Text(tab.title)
                        .font(.system(size: 11, weight: tab.id == workspace.selectedBranchTabID ? .semibold : .medium, design: .monospaced))
                        .foregroundStyle(tab.id == workspace.selectedBranchTabID ? HeedTheme.ColorToken.textPrimary : HeedTheme.ColorToken.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 30)
                        .padding(.vertical, 3)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("branch-tab-\(tab.id)")
            }
        }
    }
}
```

- [ ] **Step 4: Wire the sidebar into `WorkspaceShell`**

In `WorkspaceShell`, replace `SessionSidebarView` with:

```swift
ProjectBranchSidebarView(workspace: terminalWorkspace) {
    selectedShellMode = .newSession
}
```

Add this state near the other `@State` properties:

```swift
@State private var terminalWorkspace = TerminalShellWorkspace.preview
@State private var selectedShellMode: ShellMode = .terminal
```

Add this enum at file scope:

```swift
enum ShellMode: Equatable {
    case terminal
    case newSession
}
```

- [ ] **Step 5: Run the UI test to verify it passes**

Run:

```bash
xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' -only-testing:heedUITests/heedUITests/testRecordingShellLoadsInUITestMode test
```

Expected: PASS for sidebar assertions.

- [ ] **Step 6: Commit**

```bash
git add heed/UI/ProjectBranchSidebarView.swift heed/UI/WorkspaceShell.swift heedUITests/heedUITests.swift
git commit -m "feat: add project branch sidebar"
```

## Task 5: Build Terminal Workspace And Changed-Files Pane

**Files:**
- Create: `heed/UI/TerminalWorkspaceView.swift`
- Create: `heed/UI/ChangedFilesPane.swift`
- Modify: `heed/UI/WorkspaceShell.swift`
- Modify: `heedUITests/heedUITests.swift`

- [ ] **Step 1: Write the failing UI test**

Add these assertions to `testRecordingShellLoadsInUITestMode`:

```swift
XCTAssertTrue(app.otherElements["terminal-workspace"].exists)
XCTAssertTrue(app.buttons["terminal-tab-heed-ui-revamp-terminal-1"].exists)
XCTAssertTrue(app.staticTexts["Ready in branch context: ui-revamp"].exists)
XCTAssertTrue(app.otherElements["changed-files-pane"].exists)
XCTAssertTrue(app.staticTexts["UNSTAGED CHANGES"].exists)
XCTAssertTrue(app.staticTexts["heed/UI/WorkspaceShell.swift"].exists)
XCTAssertTrue(app.staticTexts["+ terminal tab strip"].exists)
```

- [ ] **Step 2: Run the UI test to verify it fails**

Run:

```bash
xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' -only-testing:heedUITests/heedUITests/testRecordingShellLoadsInUITestMode test
```

Expected: FAIL because the terminal workspace and changed-files pane do not exist.

- [ ] **Step 3: Create `TerminalWorkspaceView`**

Create `heed/UI/TerminalWorkspaceView.swift`:

```swift
import SwiftUI

struct TerminalWorkspaceView: View {
    let workspace: TerminalShellWorkspace

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            terminalBody
        }
        .background(HeedTheme.ColorToken.canvas)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("terminal-workspace")
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(workspace.selectedBranch?.terminals ?? []) { terminal in
                Button { } label: {
                    Text(tabTitle(for: terminal))
                        .font(.system(size: 11, weight: terminal.id == workspace.selectedTerminalID ? .semibold : .medium, design: .monospaced))
                        .foregroundStyle(terminal.id == workspace.selectedTerminalID ? HeedTheme.ColorToken.textPrimary : HeedTheme.ColorToken.textSecondary)
                        .padding(.horizontal, 14)
                        .frame(height: 38)
                        .background(terminal.id == workspace.selectedTerminalID ? Color.white.opacity(0.11) : Color.clear)
                }
                .buttonStyle(.plain)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(HeedTheme.ColorToken.borderSubtle)
                        .frame(width: HeedTheme.Stroke.brutalist)
                }
                .accessibilityIdentifier("terminal-tab-\(terminal.id)")
            }

            Button { } label: {
                Text("+")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(HeedTheme.ColorToken.textSecondary)
                    .frame(width: 42, height: 38)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("terminal-tab-add")

            Spacer(minLength: 0)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(HeedTheme.ColorToken.borderStrong)
                .frame(height: HeedTheme.Stroke.brutalist)
        }
    }

    private var terminalBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array((workspace.selectedTerminal?.promptLines ?? []).enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(color(for: line))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text("▌")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(HeedTheme.ColorToken.textSecondary.opacity(0.5))
            }
            .padding(18)
        }
        .heedHiddenScrollBars()
    }

    private func tabTitle(for terminal: TerminalShellTerminal) -> String {
        guard terminal.id == workspace.selectedTerminalID,
              let project = workspace.selectedProject,
              let branch = workspace.selectedBranch else {
            return terminal.title
        }

        return "\(project.name) / \(branch.name) / \(terminal.title)"
    }

    private func color(for line: String) -> Color {
        if line.hasPrefix("M  ") || line.hasPrefix("A  ") {
            return Color(red: 1, green: 0.87, blue: 0.36)
        }

        if line.hasPrefix("$") {
            return HeedTheme.ColorToken.textSecondary
        }

        return HeedTheme.ColorToken.textPrimary
    }
}
```

- [ ] **Step 4: Create `ChangedFilesPane`**

Create `heed/UI/ChangedFilesPane.swift`:

```swift
import SwiftUI

struct ChangedFilesPane: View {
    let files: [TerminalShellChangedFile]
    let selectedFileID: String

    var body: some View {
        VStack(spacing: 0) {
            Text("UNSTAGED CHANGES")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(HeedTheme.ColorToken.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 38)
                .padding(.horizontal, 14)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(HeedTheme.ColorToken.borderStrong)
                        .frame(height: HeedTheme.Stroke.brutalist)
                }

            fileList

            Rectangle()
                .fill(HeedTheme.ColorToken.borderSubtle)
                .frame(height: HeedTheme.Stroke.brutalist)

            selectedSummary
        }
        .frame(width: 330)
        .background(HeedTheme.ColorToken.canvas)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(HeedTheme.ColorToken.borderStrong)
                .frame(width: HeedTheme.Stroke.brutalist)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("changed-files-pane")
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(files) { file in
                HStack(spacing: 8) {
                    Text(file.status)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(HeedTheme.ColorToken.textSecondary)
                        .frame(width: 14, alignment: .leading)

                    Text(file.path)
                        .font(.system(size: 11, weight: file.id == selectedFileID ? .semibold : .medium, design: .monospaced))
                        .foregroundStyle(file.id == selectedFileID ? HeedTheme.ColorToken.textPrimary : HeedTheme.ColorToken.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
            }
        }
        .padding(14)
        .frame(maxHeight: 170, alignment: .topLeading)
    }

    private var selectedSummary: some View {
        let selectedFile = files.first { $0.id == selectedFileID } ?? files.first

        return VStack(alignment: .leading, spacing: 8) {
            if let selectedFile {
                Text(selectedFile.path)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(HeedTheme.ColorToken.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                ForEach(Array(selectedFile.summaryLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(line.hasPrefix("-") ? Color(red: 1, green: 0.48, blue: 0.45) : Color(red: 0.49, green: 0.91, blue: 0.53))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("No changed files")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(HeedTheme.ColorToken.textSecondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
```

- [ ] **Step 5: Wire both views into `WorkspaceShell`**

In `WorkspaceShell.mainWorkspace`, when `selectedShellMode == .terminal`, render:

```swift
HStack(spacing: 0) {
    TerminalWorkspaceView(workspace: terminalWorkspace)
        .frame(maxWidth: .infinity, maxHeight: .infinity)

    ChangedFilesPane(
        files: terminalWorkspace.changedFiles,
        selectedFileID: terminalWorkspace.selectedChangedFileID
    )
}
```

Keep the old `TranscriptCanvasView` available when `selectedShellMode == .newSession`.

- [ ] **Step 6: Run the UI test to verify it passes**

Run:

```bash
xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' -only-testing:heedUITests/heedUITests/testRecordingShellLoadsInUITestMode test
```

Expected: PASS for terminal and changed-files assertions.

- [ ] **Step 7: Commit**

```bash
git add heed/UI/TerminalWorkspaceView.swift heed/UI/ChangedFilesPane.swift heed/UI/WorkspaceShell.swift heedUITests/heedUITests.swift
git commit -m "feat: add terminal workspace and changed files pane"
```

## Task 6: Preserve Recording And Transcript Flow

**Files:**
- Modify: `heed/UI/WorkspaceShell.swift`
- Modify: `heedUITests/heedUITests.swift`

- [ ] **Step 1: Write the failing UI flow update**

In `testRecordingShellLoadsInUITestMode`, replace the initial empty-state expectation with:

```swift
app.buttons["sidebar-new-session"].click()
XCTAssertTrue(app.buttons["record-button"].waitForExistence(timeout: uiTimeout))
XCTAssertTrue(app.staticTexts["Press record to begin the full transcript"].waitForExistence(timeout: uiTimeout))
```

Keep the existing record, stop, transcript assertions after this point.

- [ ] **Step 2: Run the UI test to verify it fails for the new-session route**

Run:

```bash
xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' -only-testing:heedUITests/heedUITests/testRecordingShellLoadsInUITestMode test
```

Expected: FAIL until `new session` switches the center to the transcript flow and shows the bottom transport.

- [ ] **Step 3: Update `WorkspaceShell` mode routing**

Make the shell body follow this shape:

```swift
VStack(spacing: 0) {
    TopNavView(
        isSidebarVisible: $isSidebarVisible,
        searchText: $searchText
    ) {
        isAPIKeySettingsPresented = true
    }

    HStack(spacing: 0) {
        if isSidebarVisible {
            ProjectBranchSidebarView(workspace: terminalWorkspace) {
                selectedShellMode = .newSession
            }
            .transition(.move(edge: .leading).combined(with: .opacity))
        }

        mainWorkspace
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)

    if selectedShellMode == .newSession {
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
}
```

Inside `mainWorkspace`, use this mode switch:

```swift
switch selectedShellMode {
case .terminal:
    HStack(spacing: 0) {
        TerminalWorkspaceView(workspace: terminalWorkspace)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        ChangedFilesPane(
            files: terminalWorkspace.changedFiles,
            selectedFileID: terminalWorkspace.selectedChangedFileID
        )
    }
case .newSession:
    transcriptWorkspace
}
```

Extract the existing transcript and task-prep switch into:

```swift
@ViewBuilder
private var transcriptWorkspace: some View {
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
```

- [ ] **Step 4: Ensure task prep forces transcript mode**

Add this change to the existing task-prep state observer:

```swift
.onChange(of: taskPrepController.activeTaskID) {
    if taskPrepController.activeTaskID != nil {
        selectedShellMode = .newSession
    }
}
```

- [ ] **Step 5: Run the UI test to verify recording passes**

Run:

```bash
xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' -only-testing:heedUITests/heedUITests/testRecordingShellLoadsInUITestMode test
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add heed/UI/WorkspaceShell.swift heedUITests/heedUITests.swift
git commit -m "feat: preserve recording flow in terminal shell"
```

## Task 7: Preserve Compile And Task Prep Flow

**Files:**
- Modify: `heedUITests/heedUITests.swift`
- Modify: `heed/UI/WorkspaceShell.swift`

- [ ] **Step 1: Write the failing UI flow update**

In `testCompileTasksFlowAppearsInlineAfterRecordingStops`, click `new session` before clicking record:

```swift
XCTAssertTrue(app.buttons["sidebar-new-session"].waitForExistence(timeout: uiTimeout))
app.buttons["sidebar-new-session"].click()
XCTAssertTrue(app.buttons["record-button"].waitForExistence(timeout: uiTimeout))
```

Keep the existing compile and task-prep assertions.

- [ ] **Step 2: Run the UI test to verify it fails or exposes missing route behavior**

Run:

```bash
xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' -only-testing:heedUITests/heedUITests/testCompileTasksFlowAppearsInlineAfterRecordingStops test
```

Expected: FAIL if compile, prep, or source jump gets hidden by the new shell mode.

- [ ] **Step 3: Keep compile actions in the transcript utility rail**

Confirm `trailingUtilityActions` still returns:

```swift
["Recompile", "Set API key", "Copy text", "Full screen"]
```

after compilation succeeds. Do not move `Compile tasks` into the terminal fixture in this pass.

- [ ] **Step 4: Keep task prep visible inside transcript mode**

When `TaskAnalysisSectionView` calls:

```swift
taskPrepController.start(task: task, in: displayedSession)
```

the observer from Task 6 should switch `selectedShellMode` to `.newSession`. This keeps `TaskPrepWorkspaceView` reachable with the existing `task-prep-workspace` identifier.

- [ ] **Step 5: Run the compile and prep UI test**

Run:

```bash
xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' -only-testing:heedUITests/heedUITests/testCompileTasksFlowAppearsInlineAfterRecordingStops test
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add heed/UI/WorkspaceShell.swift heedUITests/heedUITests.swift
git commit -m "feat: preserve task prep in terminal shell"
```

## Task 8: Update Docs

**Files:**
- Modify: `README.md`
- Modify: `docs/FRONTEND.md`

- [ ] **Step 1: Update README wording**

In `README.md`, replace the current shell summary with:

```markdown
The app now opens into a brutalist terminal-first shell. The top nav contains the sidebar toggle, search, `Open IDE`, and settings. The left sidebar lists `tasks`, `new session`, projects, branches, and branch-specific side tabs. The center pane shows terminal tabs for the selected branch. The right pane shows unstaged changed files and readable summaries. The recording and transcript flow stays available from `new session`, and task prep still opens from compiled transcript tasks.
```

- [ ] **Step 2: Update frontend doc current UI surface**

In `docs/FRONTEND.md`, update `Current UI Surface` to say:

```markdown
The app opens into a brutalist terminal-first shell. The primary canvas is black, with high-contrast white borders. A full-width top nav holds the sidebar toggle, search, `Open IDE`, and settings. The left sidebar lists `tasks`, `new session`, projects, branches, and branch-specific tabs. The center pane shows terminal tabs for the selected branch. The right pane shows unstaged changed files and readable summaries, not raw code editing.

The recording and transcript flow remains available through `new session`. When that mode is active, the existing transcript canvas, floating record button, utility rail, compile flow, and task-prep workspace continue to use the existing controllers.
```

- [ ] **Step 3: Run a docs diff**

Run:

```bash
git diff -- README.md docs/FRONTEND.md
```

Expected: The diff describes shipped behavior after the code changes.

- [ ] **Step 4: Commit**

```bash
git add README.md docs/FRONTEND.md
git commit -m "docs: update terminal shell UI docs"
```

## Task 9: Final Verification

**Files:**
- Verify all changed files.

- [ ] **Step 1: Run unit tests**

Run:

```bash
xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' -only-testing:heedTests test
```

Expected: PASS.

- [ ] **Step 2: Run UI tests**

Run:

```bash
xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' -only-testing:heedUITests test
```

Expected: PASS, except `testLaunchPerformance` remains skipped by design.

- [ ] **Step 3: Run a full build**

Run:

```bash
xcodebuild -project heed.xcodeproj -scheme heed -destination 'platform=macOS' build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Review changed files**

Run:

```bash
git status --short
git diff --stat
```

Expected: Only files from this plan changed.

- [ ] **Step 5: Manual visual check**

Open the app in Xcode or run the built app. Confirm:

- First screen reads as a black brutalist terminal shell.
- Top nav has the sidebar icon, search, `Open IDE`, and settings.
- Sidebar has `tasks`, `new session`, projects, branches, and branch tabs.
- Center has terminal tabs.
- Right pane has changed files and summaries.
- Clicking `new session` shows the transcript flow.
- Recording still starts and stops in demo mode.

- [ ] **Step 6: Final commit if verification changed docs or tests**

If final verification required any fixes, commit them:

```bash
git add README.md docs/FRONTEND.md heed/UI heedTests heedUITests
git commit -m "fix: complete terminal shell verification"
```

If no fixes were needed, do not create an empty commit.

## Self-Review

Spec coverage:

- Brutalist black UI: covered by Task 2.
- Top nav: covered by Task 3.
- Left sidebar structure: covered by Task 4.
- Branch-specific side tabs: covered by Tasks 1 and 4.
- Center terminal tabs: covered by Task 5.
- Right changed-files pane: covered by Task 5.
- Existing recording and task-prep reachability: covered by Tasks 6 and 7.
- No persistence, permission, entitlement, or saved-data changes: enforced by file structure and tasks.

Placeholder scan:

- No placeholder markers are used.
- Fixture UI state is explicit in `TerminalShellWorkspace.preview`.

Type consistency:

- `TerminalShellWorkspace`, `TerminalShellProject`, `TerminalShellBranch`, `TerminalShellBranchTab`, `TerminalShellTerminal`, and `TerminalShellChangedFile` names match across tasks.
- UI identifiers match the UI test assertions.
