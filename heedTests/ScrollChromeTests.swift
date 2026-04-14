import AppKit
import Testing
@testable import heed

struct ScrollChromeTests {
    @MainActor
    @Test func hiddenScrollBarConfigurationDisablesBothScrollers() {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.scrollerStyle = .legacy

        HeedScrollChrome.hideScrollBars(in: scrollView)

        #expect(scrollView.hasVerticalScroller == false)
        #expect(scrollView.hasHorizontalScroller == false)
        #expect(scrollView.autohidesScrollers == true)
        #expect(scrollView.scrollerStyle == .overlay)
    }
}
