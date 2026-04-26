import SwiftUI

struct TaskPrepTerminalView: View {
    @ObservedObject var controller: TaskPrepController

    var body: some View {
        TerminalCanvasView(
            text: terminalText,
            isRunning: canSendInput,
            onInput: controller.sendTerminalInput
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black)
        .accessibilityIdentifier("task-prep-terminal")
    }

    private var terminalText: String {
        let output = controller.viewState.terminalOutput
        return output.isEmpty ? statusText : output
    }

    private var canSendInput: Bool {
        if case .running = controller.viewState.terminalStatus {
            return true
        }

        return false
    }

    var statusText: String {
        switch controller.viewState.terminalStatus {
        case .idle:
            return "Waiting for spawn approval."
        case .launching:
            return "Starting Codex."
        case .running:
            return "Codex is running."
        case let .failed(message):
            return message
        case let .ended(exitCode):
            if let exitCode {
                return "Codex exited with code \(exitCode)."
            }

            return "Codex exited."
        }
    }
}

struct TerminalCanvasView: NSViewRepresentable {
    let text: String
    let isRunning: Bool
    let onInput: (String) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = TerminalScrollView()
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .black
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = TerminalTextView()
        textView.onInput = onInput
        textView.isRunning = isRunning
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = .black
        textView.textColor = .white
        textView.insertionPointColor = .white
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        TerminalCanvasLayout.configure(textView, in: scrollView)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.string = text

        scrollView.documentView = textView
        TerminalCanvasLayout.resize(textView, in: scrollView)
        context.coordinator.textView = textView
        DispatchQueue.main.async {
            scrollView.window?.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else {
            return
        }

        textView.onInput = onInput
        textView.isRunning = isRunning
        TerminalCanvasLayout.resize(textView, in: scrollView)

        if textView.string != text {
            textView.string = text
            TerminalCanvasLayout.resize(textView, in: scrollView)
            textView.scrollToEndOfDocument(nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        weak var textView: TerminalTextView?
    }
}

final class TerminalScrollView: NSScrollView {
    override func layout() {
        super.layout()

        guard let textView = documentView as? TerminalTextView else {
            return
        }

        TerminalCanvasLayout.resize(textView, in: self)
    }
}

enum TerminalCanvasLayout {
    nonisolated static let minimumContentWidth: CGFloat = 320
    nonisolated static let textContainerInset = NSSize(width: 16, height: 14)

    @MainActor
    static func configure(_ textView: NSTextView, in scrollView: NSScrollView) {
        textView.textContainerInset = textContainerInset
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
    }

    @MainActor
    static func resize(_ textView: NSTextView, in scrollView: NSScrollView) {
        let contentSize = scrollView.contentSize
        let contentWidth = max(contentSize.width, minimumContentWidth)
        let contentHeight = max(contentSize.height, textView.frame.height)
        textView.frame = NSRect(
            origin: .zero,
            size: NSSize(width: contentWidth, height: contentHeight)
        )
        textView.textContainer?.containerSize = NSSize(
            width: textContainerWidth(for: contentWidth),
            height: CGFloat.greatestFiniteMagnitude
        )
    }

    nonisolated static func textContainerWidth(for contentWidth: CGFloat) -> CGFloat {
        max(1, max(contentWidth, minimumContentWidth) - (textContainerInset.width * 2))
    }
}

final class TerminalTextView: NSTextView {
    var onInput: (String) -> Void = { _ in }
    var isRunning = false

    override var acceptsFirstResponder: Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        guard isRunning else {
            return
        }

        guard let input = TerminalKeyMapper.input(for: event) else {
            super.keyDown(with: event)
            return
        }

        onInput(input)
    }
}

enum TerminalKeyMapper {
    nonisolated static func input(
        characters: String?,
        charactersIgnoringModifiers: String?,
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags
    ) -> String? {
        switch keyCode {
        case 36, 76:
            return "\r"
        case 51:
            return "\u{7F}"
        case 53:
            return "\u{1B}"
        case 123:
            return "\u{1B}[D"
        case 124:
            return "\u{1B}[C"
        case 125:
            return "\u{1B}[B"
        case 126:
            return "\u{1B}[A"
        default:
            break
        }

        if modifierFlags.contains(.control),
           let character = charactersIgnoringModifiers?.unicodeScalars.first {
            let value = character.value
            if value >= 64, value <= 95 {
                return String(UnicodeScalar(value - 64)!)
            }
            if value >= 97, value <= 122 {
                return String(UnicodeScalar(value - 96)!)
            }
        }

        return characters
    }

    nonisolated static func input(for event: NSEvent) -> String? {
        input(
            characters: event.characters,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            keyCode: event.keyCode,
            modifierFlags: event.modifierFlags
        )
    }
}
