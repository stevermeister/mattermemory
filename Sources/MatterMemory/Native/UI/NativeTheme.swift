import SwiftUI

/// Mattermost "Denim" (light) and "Onyx" (dark) palettes.
struct MMTheme {
    let sidebarBg, sidebarHeaderBg, sidebarText, sidebarTextDim, sidebarHover, sidebarActive, sidebarActiveBorder: Color
    let centerBg, centerText, centerTextDim, divider, link, buttonBg, buttonText, mentionBg, mentionText, newMessage, codeBg, hoverBg: Color
    let online, away, dnd, offline: Color

    static func current(_ scheme: ColorScheme) -> MMTheme { scheme == .dark ? onyx : denim }

    static let denim = MMTheme(
        sidebarBg: hex(0x1e325c), sidebarHeaderBg: hex(0x192a4d), sidebarText: .white, sidebarTextDim: Color.white.opacity(0.64),
        sidebarHover: Color.white.opacity(0.08), sidebarActive: Color.white.opacity(0.16), sidebarActiveBorder: hex(0x5d89ea),
        centerBg: .white, centerText: hex(0x3f4350), centerTextDim: hex(0x3f4350).opacity(0.64), divider: hex(0x3f4350).opacity(0.12),
        link: hex(0x386fe5), buttonBg: hex(0x1c58d9), buttonText: .white, mentionBg: .white, mentionText: hex(0x1e325c),
        newMessage: hex(0xcc8f00), codeBg: hex(0x3f4350).opacity(0.06), hoverBg: hex(0x3f4350).opacity(0.04),
        online: hex(0x3db887), away: hex(0xffbc1f), dnd: hex(0xd24b4e), offline: hex(0x3f4350).opacity(0.4))

    static let onyx = MMTheme(
        sidebarBg: hex(0x121317), sidebarHeaderBg: hex(0x1b1d22), sidebarText: hex(0xdddfe4), sidebarTextDim: hex(0xdddfe4).opacity(0.64),
        sidebarHover: Color.white.opacity(0.08), sidebarActive: Color.white.opacity(0.12), sidebarActiveBorder: hex(0x5d89ea),
        centerBg: hex(0x1b1d22), centerText: hex(0xdddfe4), centerTextDim: hex(0xdddfe4).opacity(0.64), divider: hex(0xdddfe4).opacity(0.12),
        link: hex(0x5d89ea), buttonBg: hex(0x1c58d9), buttonText: .white, mentionBg: hex(0xdddfe4), mentionText: hex(0x121317),
        newMessage: hex(0xcc8f00), codeBg: hex(0xdddfe4).opacity(0.08), hoverBg: hex(0xdddfe4).opacity(0.06),
        online: hex(0x3db887), away: hex(0xffbc1f), dnd: hex(0xd24b4e), offline: hex(0xdddfe4).opacity(0.4))

    private static func hex(_ v: UInt32) -> Color {
        Color(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }
}

private struct ThemeKey: EnvironmentKey { static let defaultValue = MMTheme.denim }
extension EnvironmentValues {
    var mmTheme: MMTheme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
