import SwiftUI

enum HeedTheme {
    enum ColorToken {
        static let canvas = Color(red: 0.02, green: 0.02, blue: 0.02)
        static let panel = Color(red: 0.05, green: 0.05, blue: 0.05)
        static let panelRaised = Color(red: 0.09, green: 0.09, blue: 0.09)
        static let textPrimary = Color(red: 0.96, green: 0.96, blue: 0.94)
        static let textSecondary = Color(red: 0.58, green: 0.58, blue: 0.55)
        static let borderSubtle = Color.white.opacity(0.14)
        static let borderStrong = Color.white.opacity(0.28)
        static let shadow = Color.black.opacity(0.38)
        static let recording = Color(red: 0.88, green: 0.15, blue: 0.18)
        static let warning = Color(red: 0.73, green: 0.54, blue: 0.20)
        static let success = Color(red: 0.38, green: 0.72, blue: 0.46)
        static let actionYellow = Color(red: 0.72, green: 0.91, blue: 0.20)
    }

    enum Space {
        static let xxxs: CGFloat = 4
        static let xxs: CGFloat = 6
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Corner {
        static let pill: CGFloat = 999
        static let panel: CGFloat = 18
        static let button: CGFloat = 14
    }

    enum Stroke {
        static let hairline: CGFloat = 1
        static let emphasis: CGFloat = 1.5
    }

    enum Layout {
        static let floatingTransportMinHeight: CGFloat = 72
        static let floatingTransportMinWidth: CGFloat = 264
        static let floatingTransportMaxWidth: CGFloat = 360
        static let floatingTransportBottomInset: CGFloat = 20
        static let floatingTransportHorizontalInset: CGFloat = 16
        static let transportButtonHeight: CGFloat = 44
        static let transportButtonMinWidth: CGFloat = 118
    }

    enum Typography {
        static let utilityLabel = Font.system(size: 11, weight: .semibold, design: .monospaced)
        static let utilityValue = Font.system(size: 12, weight: .bold, design: .monospaced)
        static let button = Font.system(size: 14, weight: .bold, design: .monospaced)
    }

    enum Motion {
        static let quick = Animation.easeOut(duration: 0.16)
        static let settle = Animation.spring(response: 0.24, dampingFraction: 0.84)
    }
}
