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
            .accessibilityLabel("Toggle sidebar")
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
                .disabled(true)

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
            .accessibilityLabel("Open settings")
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
