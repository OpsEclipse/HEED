import SwiftUI

struct UtilityRailView: View {
    let primaryStatus: String
    let secondaryStatus: String?
    let details: [Detail]
    let actions: [Action]
    let primaryControl: AnyView

    init<PrimaryControl: View>(
        primaryStatus: String,
        secondaryStatus: String?,
        details: [Detail],
        actions: [Action],
        @ViewBuilder primaryControl: () -> PrimaryControl
    ) {
        self.primaryStatus = primaryStatus
        self.secondaryStatus = secondaryStatus
        self.details = details
        self.actions = actions
        self.primaryControl = AnyView(primaryControl())
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            regularLayout
            compactLayout
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(UtilityRailPalette.canvas)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(UtilityRailPalette.divider)
                .frame(height: 1)
        }
    }

    private var regularLayout: some View {
        HStack(alignment: .center, spacing: 20) {
            statusBlock
                .frame(maxWidth: .infinity, alignment: .leading)

            primaryControl
                .fixedSize()

            actionRow
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 14) {
            statusBlock
            primaryControl
                .frame(maxWidth: .infinity, alignment: .leading)
            compactActionColumn
        }
    }

    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                Text(primaryStatus)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(UtilityRailPalette.primaryText)

                if let secondaryStatus, !secondaryStatus.isEmpty {
                    Text(secondaryStatus)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(UtilityRailPalette.secondaryText)
                }
            }

            if !detailLine.isEmpty {
                Text(detailLine)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(UtilityRailPalette.secondaryText)
                    .lineLimit(2)
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 14) {
            ForEach(actions) { action in
                actionButton(for: action)
            }
        }
    }

    private var compactActionColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(actions) { action in
                actionButton(for: action)
            }
        }
    }

    private func actionButton(for action: Action) -> some View {
        Button(role: action.role.buttonRole) {
            action.handler()
        } label: {
            Text(action.title)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(action.role.foregroundColor)
        }
        .buttonStyle(.plain)
        .disabled(!action.isEnabled)
        .opacity(action.isEnabled ? 0.82 : 0.3)
        .accessibilityIdentifier(action.accessibilityIdentifier ?? action.id)
    }

    private var detailLine: String {
        details
            .map(\.displayText)
            .filter { !$0.isEmpty }
            .joined(separator: "  •  ")
    }
}

extension UtilityRailView {
    struct Detail: Identifiable {
        let id: String
        let label: String
        let value: String?

        init(id: String? = nil, label: String, value: String? = nil) {
            self.id = id ?? label
            self.label = label
            self.value = value
        }

        var displayText: String {
            guard let value, !value.isEmpty else {
                return label
            }

            return "\(label) \(value)"
        }
    }

    struct Action: Identifiable {
        enum Role {
            case normal
            case warning

            fileprivate var buttonRole: ButtonRole? {
                switch self {
                case .normal:
                    return nil
                case .warning:
                    return .destructive
                }
            }

            fileprivate var foregroundColor: Color {
                switch self {
                case .normal:
                    return UtilityRailPalette.primaryText
                case .warning:
                    return UtilityRailPalette.warningText
                }
            }
        }

        let id: String
        let title: String
        let detail: String?
        let isEnabled: Bool
        let role: Role
        let accessibilityIdentifier: String?
        let handler: () -> Void

        init(
            id: String,
            title: String,
            detail: String? = nil,
            isEnabled: Bool = true,
            role: Role = .normal,
            accessibilityIdentifier: String? = nil,
            handler: @escaping () -> Void
        ) {
            self.id = id
            self.title = title
            self.detail = detail
            self.isEnabled = isEnabled
            self.role = role
            self.accessibilityIdentifier = accessibilityIdentifier
            self.handler = handler
        }
    }
}

private enum UtilityRailPalette {
    static let canvas = HeedTheme.ColorToken.canvas
    static let divider = Color.white.opacity(0.08)
    static let primaryText = Color.white.opacity(0.56)
    static let secondaryText = Color.white.opacity(0.32)
    static let warningText = Color(red: 0.88, green: 0.67, blue: 0.36)
}

#Preview("Regular") {
    UtilityRailView(
        primaryStatus: "Ready to record",
        secondaryStatus: "Local capture",
        details: [
            .init(label: "Mode", value: "Mic + system"),
            .init(label: "Auto-scroll", value: "On"),
            .init(label: "Model", value: "ggml-base.en")
        ],
        actions: [
            .init(id: "copy", title: "Copy as text") {}
        ]
    ) {
        FloatingTransportView(recordingState: .ready) { }
    }
    .frame(width: 900)
    .background(Color.black)
}

#Preview("Compact") {
    UtilityRailView(
        primaryStatus: "Recording locally",
        secondaryStatus: "00:09:42 elapsed",
        details: [
            .init(label: "Mode", value: "Mic + system"),
            .init(label: "Auto-scroll", value: "Off")
        ],
        actions: [
            .init(id: "copy", title: "Copy as text", isEnabled: false) {}
        ]
    ) {
        FloatingTransportView(recordingState: .recording) { }
    }
    .frame(width: 360)
    .background(Color.black)
}
