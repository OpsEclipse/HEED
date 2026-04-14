import SwiftUI

struct FloatingTransportView: View {
    let recordingState: RecordingState
    let isEnabled: Bool
    let onPrimaryAction: () -> Void

    init(
        recordingState: RecordingState,
        isEnabled: Bool = true,
        onPrimaryAction: @escaping () -> Void
    ) {
        self.recordingState = recordingState
        self.isEnabled = isEnabled
        self.onPrimaryAction = onPrimaryAction
    }

    var body: some View {
        primaryButton
    }

    private var primaryButton: some View {
        Button(actionLabel, action: onPrimaryAction)
            .buttonStyle(
                HeedTransportButtonStyle(
                    fillColor: buttonFill,
                    textColor: buttonTextColor,
                    size: .primary
                )
            )
            .disabled(!isEnabled || recordingState == .stopping || recordingState == .requestingPermissions || recordingState == .processing)
            .accessibilityIdentifier("record-button")
    }

    private var actionLabel: String {
        recordingState == .recording ? "Stop" : "Record"
    }

    private var buttonFill: Color {
        HeedTheme.ColorToken.actionYellow
    }

    private var buttonTextColor: Color {
        Color.black.opacity(0.86)
    }
}

enum HeedTransportButtonSize {
    case primary
    case compact
}

struct HeedTransportButtonStyle: ButtonStyle {
    let fillColor: Color
    let textColor: Color
    let size: HeedTransportButtonSize

    init(fillColor: Color, textColor: Color, size: HeedTransportButtonSize = .primary) {
        self.fillColor = fillColor
        self.textColor = textColor
        self.size = size
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: fontSize, weight: .semibold, design: .default))
            .foregroundStyle(textColor.opacity(configuration.isPressed ? 0.82 : 1))
            .frame(minWidth: minWidth, minHeight: minHeight)
            .padding(.horizontal, horizontalPadding)
            .background(buttonShape.fill(fillColor.opacity(configuration.isPressed ? pressedOpacity : normalOpacity)))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(HeedTheme.Motion.quick, value: configuration.isPressed)
    }

    private var fontSize: CGFloat {
        switch size {
        case .primary:
            return 15
        case .compact:
            return 12
        }
    }

    private var minWidth: CGFloat {
        switch size {
        case .primary:
            return 132
        case .compact:
            return 0
        }
    }

    private var minHeight: CGFloat {
        switch size {
        case .primary:
            return 44
        case .compact:
            return 34
        }
    }

    private var horizontalPadding: CGFloat {
        switch size {
        case .primary:
            return 18
        case .compact:
            return 12
        }
    }

    private var normalOpacity: Double {
        switch size {
        case .primary:
            return 1
        case .compact:
            return 0.92
        }
    }

    private var pressedOpacity: Double {
        switch size {
        case .primary:
            return 0.86
        case .compact:
            return 0.82
        }
    }

    private var buttonShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size == .primary ? 8 : 7, style: .continuous)
    }
}

#Preview("Idle") {
    previewContainer {
        FloatingTransportView(recordingState: .idle) { }
    }
}

#Preview("Ready") {
    previewContainer {
        FloatingTransportView(recordingState: .ready) { }
    }
}

#Preview("Recording") {
    previewContainer {
        FloatingTransportView(recordingState: .recording) { }
    }
}

#Preview("Stopping") {
    previewContainer {
        FloatingTransportView(recordingState: .stopping) { }
    }
}

#Preview("Processing") {
    previewContainer {
        FloatingTransportView(recordingState: .processing) { }
    }
}

#Preview("Blocked") {
    previewContainer {
        FloatingTransportView(
            recordingState: .error("Screen recording is still off"),
            isEnabled: false
        ) { }
    }
}

private func previewContainer<Content: View>(
    @ViewBuilder content: () -> Content
) -> some View {
    ZStack {
        HeedTheme.ColorToken.canvas.ignoresSafeArea()
        VStack {
            Spacer()
            content()
                .padding(.bottom, HeedTheme.Layout.floatingTransportBottomInset)
        }
        .padding(.horizontal, HeedTheme.Layout.floatingTransportHorizontalInset)
    }
    .frame(width: 900, height: 640)
}
