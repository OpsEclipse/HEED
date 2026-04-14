import AppKit
import SwiftUI

enum HeedScrollChrome {
    @MainActor
    static func hideScrollBars(in scrollView: NSScrollView) {
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScroller?.isHidden = true
        scrollView.horizontalScroller?.isHidden = true
    }
}

extension View {
    func heedHiddenScrollBars() -> some View {
        background(HeedScrollBarHider())
    }

    func heedHiddenWindowScrollBars() -> some View {
        background(HeedWindowScrollBarSuppressor())
    }
}

private struct HeedScrollBarHider: NSViewRepresentable {
    func makeNSView(context: Context) -> HeedScrollBarHiderView {
        HeedScrollBarHiderView()
    }

    func updateNSView(_ nsView: HeedScrollBarHiderView, context: Context) {
        nsView.applyIfNeeded()
    }
}

private final class HeedScrollBarHiderView: NSView {
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        applyIfNeeded()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyIfNeeded()
    }

    func applyIfNeeded() {
        guard let scrollView = enclosingScrollView else {
            return
        }

        Task { @MainActor in
            HeedScrollChrome.hideScrollBars(in: scrollView)
        }
    }
}

private struct HeedWindowScrollBarSuppressor: NSViewRepresentable {
    func makeNSView(context: Context) -> HeedWindowScrollBarSuppressorView {
        HeedWindowScrollBarSuppressorView()
    }

    func updateNSView(_ nsView: HeedWindowScrollBarSuppressorView, context: Context) {
        nsView.applyIfNeeded()
    }
}

private final class HeedWindowScrollBarSuppressorView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyIfNeeded()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        applyIfNeeded()
    }

    func applyIfNeeded() {
        guard let rootView = window?.contentView else {
            return
        }

        Task { @MainActor in
            HeedScrollChrome.hideScrollBars(inHierarchyOf: rootView)
        }
    }
}

private extension HeedScrollChrome {
    @MainActor
    static func hideScrollBars(inHierarchyOf rootView: NSView) {
        for subview in rootView.subviews {
            if let scrollView = subview as? NSScrollView {
                hideScrollBars(in: scrollView)
            }

            hideScrollBars(inHierarchyOf: subview)
        }
    }
}
