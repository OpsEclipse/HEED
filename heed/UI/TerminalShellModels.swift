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
