import SwiftUI

enum HeedTheme {
    enum ColorToken {
        static let canvas = Color.black
        static let panel = Color.black
        static let panelRaised = Color(red: 0.04, green: 0.04, blue: 0.04)
        static let textPrimary = Color.white
        static let textSecondary = Color.white.opacity(0.58)
        static let borderSubtle = Color.white.opacity(Opacity.brutalistDivider)
        static let borderStrong = Color.white.opacity(Opacity.brutalistBorder)
        static let shadow = Color.black.opacity(0.38)
        static let recording = Color(red: 0.88, green: 0.15, blue: 0.18)
        static let warning = Color(red: 0.73, green: 0.54, blue: 0.20)
        static let success = Color(red: 0.38, green: 0.72, blue: 0.46)
        static let actionYellow = Color(red: 0.72, green: 0.91, blue: 0.20)
    }

    enum Opacity {
        static let brutalistBorder: Double = 0.6
        static let brutalistDivider: Double = 0.3
        static let disabled: Double = 0.32
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
        static let brutalist: CGFloat = 0
        static let pill: CGFloat = 999
        static let panel: CGFloat = 8
        static let button: CGFloat = 0
    }

    enum Stroke {
        static let hairline: CGFloat = 1
        static let emphasis: CGFloat = 1.5
        static let brutalist: CGFloat = 1
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
