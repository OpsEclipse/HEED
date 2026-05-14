import SwiftUI

struct ChangedFilesPane: View {
    let files: [TerminalShellChangedFile]
    let selectedFileID: String

    private var selectedFile: TerminalShellChangedFile? {
        files.first { $0.id == selectedFileID }
            ?? files.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if files.isEmpty {
                emptyState
            } else {
                changedFilesList
                selectedFileSummary
            }
        }
        .frame(width: 330)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(HeedTheme.ColorToken.canvas)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(HeedTheme.ColorToken.borderStrong)
                .frame(width: HeedTheme.Stroke.emphasis)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("changed-files-pane")
    }

    private var header: some View {
        Text("UNSTAGED CHANGES")
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundStyle(HeedTheme.ColorToken.textPrimary)
            .tracking(0)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 42)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(HeedTheme.ColorToken.borderStrong)
                    .frame(height: HeedTheme.Stroke.brutalist)
            }
    }

    private var emptyState: some View {
        Text("No changed files")
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(HeedTheme.ColorToken.textSecondary)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var changedFilesList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(files) { file in
                changedFileRow(file)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(HeedTheme.ColorToken.borderSubtle)
                .frame(height: HeedTheme.Stroke.brutalist)
        }
    }

    private func changedFileRow(_ file: TerminalShellChangedFile) -> some View {
        let isSelected = file.id == selectedFile?.id

        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(file.status)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(isSelected ? HeedTheme.ColorToken.actionYellow : HeedTheme.ColorToken.textSecondary)
                .frame(width: 18, alignment: .leading)

            Text(file.path)
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium, design: .monospaced))
                .foregroundStyle(isSelected ? HeedTheme.ColorToken.textPrimary : HeedTheme.ColorToken.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(isSelected ? Color.white.opacity(0.10) : Color.clear)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var selectedFileSummary: some View {
        if let selectedFile {
            VStack(alignment: .leading, spacing: 10) {
                Text(selectedFile.path)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(HeedTheme.ColorToken.textPrimary)
                    .lineLimit(2)
                    .textSelection(.enabled)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(selectedFile.summaryLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(line.hasPrefix("-") ? HeedTheme.ColorToken.textSecondary : HeedTheme.ColorToken.actionYellow)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
