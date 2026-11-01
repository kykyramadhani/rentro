import SwiftUI

// Semantic Light/Dark tokens from Figma variables (file CPVUgH5MmmOvlx3ArxEF94, nodes 43:579 / 43:1054, 43:684 / 43:1159).
private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }

    static let brandSolid = Color(light: 0x135b57, dark: 0x144943)
    static let brandSelected = Color(light: 0x187366, dark: 0x65dabd)
    static let textOnBrand = Color.white
    static let textHeaderSecondary = Color(light: 0xcfe8e1, dark: 0xcfe8e1)
    static let textPrimary = Color(light: 0x162724, dark: 0xeff8f5)
    static let textSecondary = Color(light: 0x4f625e, dark: 0xa5bbb5)      // Figma light #78908b is 3.2:1; darkened to ~6:1 so thin caption text still passes
    static let textAccent = Color(light: 0x135b57, dark: 0xa8e3cc)
    static let textOnSoft = Color(light: 0x104a47, dark: 0xd6f0e8)
    static let textSuccess = Color(light: 0x126b50, dark: 0x88dbb0)        // Figma #167d5d is 4.46:1 on its pill; ~5.7:1 here
    static let textWarning = Color(light: 0x855421, dark: 0xffba85)        // Figma #ba762f is 3.3:1 on its pill; ~5.7:1 here
    static let textDanger = Color(light: 0x9e3e3e, dark: 0xff9da3)         // Figma #c44e4e is 4.0:1 on its pill; ~5.7:1 here
    static let bgCanvas = Color(light: 0xf7f9f8, dark: 0x101817)
    static let bgSurface = Color(light: 0xffffff, dark: 0x1d2927)
    static let bgSubtle = Color(light: 0xeff4f2, dark: 0x263633)
    static let bgSuccess = Color(light: 0xe3f4ea, dark: 0x25463a)
    static let bgWarning = Color(light: 0xfff0e9, dark: 0x50392a)
    static let bgDanger = Color(light: 0xfcecec, dark: 0x522f33)
    static let iconDefault = Color(light: 0x17675d, dark: 0xbeede1)
    static let iconWarning = Color(light: 0xb65d25, dark: 0xffba85)
}

enum Space { static let s4: CGFloat = 4, s8: CGFloat = 8, s12: CGFloat = 12, s16: CGFloat = 16, s20: CGFloat = 20, s24: CGFloat = 24 }
enum Radius { static let r12: CGFloat = 12, r16: CGFloat = 16 }
