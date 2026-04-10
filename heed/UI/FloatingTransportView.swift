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
                    textColor: buttonTextColor
                )
            )
            .disabled(!isEnabled || recordingState == .stopping || recordingState == .requestingPermissions)
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

private struct HeedTransportButtonStyle: ButtonStyle {
    let fillColor: Color
    let textColor: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold, design: .default))
            .foregroundStyle(textColor.opacity(configuration.isPressed ? 0.82 : 1))
            .frame(
                minWidth: 132,
                minHeight: 44
            )
            .padding(.horizontal, 18)
            .background(buttonShape.fill(fillColor.opacity(configuration.isPressed ? 0.86 : 1)))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(HeedTheme.Motion.quick, value: configuration.isPressed)
    }

    private var buttonShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
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
