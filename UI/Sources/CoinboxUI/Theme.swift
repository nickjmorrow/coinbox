import SwiftUI

/// Ember: night-mode indigo ink with a fire accent, taken from the app icon (an ember flame on an ink tile).
/// Ember is the one tint and belongs to things you can act on; gold is kept for records, completion is mint, destructive is rose, everything else is ink and text.
public enum Theme {
    // Surfaces, darkest to lightest
    public static let background = Color(hex: 0x0a0b19)   // ink 950: screens
    public static let bar = Color(hex: 0x0e1021)          // ink 900: bars and sheets
    public static let card = Color(hex: 0x13162b)         // ink 850: grouped content
    public static let field = Color(hex: 0x1a1d38)        // ink 800: inputs and quiet buttons
    public static let raised = Color(hex: 0x252950)       // ink 700: pressed and selected fills
    public static let line = Color(hex: 0x33386a)         // ink 600: separators and outlines

    // Text. `faint` is 3.9:1 on a card, so it is for decoration and disabled states only, never for reading.
    public static let text = Color(hex: 0xe8eaf8)
    public static let dim = Color(hex: 0xa6abcf)          // 7.9:1 on a card: secondary text and placeholders
    public static let faint = Color(hex: 0x6f7499)

    public static let accent = Color(hex: 0xff8a3d)       // ember, 7.6:1 on a card
    public static let accentBright = Color(hex: 0xffa55c)
    public static let flameTop = Color(hex: 0xffb347)     // the icon's flame, top to bottom: primary buttons only
    public static let flameBottom = Color(hex: 0xff6a2b)
    public static let gold = Color(hex: 0xffd25a)         // personal records only
    public static let done = Color(hex: 0x5fe3b4)
    public static let danger = Color(hex: 0xff5c8a)       // rose, kept clear of the ember accent
    public static let info = Color(hex: 0x67c6ff)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }

    /// Kept as aliases so older call sites read the theme.
    static let coinbox = Theme.accent
    static var cardBackground: Color { Theme.card }
    static var screenBackground: Color { Theme.background }
}

/// Motion: quick and decelerating, never bouncy. With Reduce Motion on, movement becomes a short fade and state changes still read.
extension Animation {
    static let snappyUI = Animation.snappy(duration: 0.28)
    static let settleUI = Animation.smooth(duration: 0.4)
}

private struct MotionModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: Value
    func body(content: Content) -> some View { content.animation(reduceMotion ? .easeOut(duration: 0.12) : animation, value: value) }
}

private struct AppearTransition: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let edge: Edge
    func body(content: Content) -> some View {
        content.transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: edge).combined(with: .opacity), removal: .opacity.combined(with: .scale(scale: 0.96))))
    }
}

extension View {
    /// Animates changes of `value`, honoring Reduce Motion.
    func motion<Value: Equatable>(_ animation: Animation = .snappyUI, value: Value) -> some View { modifier(MotionModifier(animation: animation, value: value)) }

    /// Rows and bars that arrive from an edge and leave with a fade.
    func appears(from edge: Edge = .bottom) -> some View { modifier(AppearTransition(edge: edge)) }
}

/// The primary action: the icon's flame gradient, ink label (6.8:1 at the darkest), a 44-pt target.
struct AccentButtonStyle: ButtonStyle {
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.background)
            .frame(maxWidth: compact ? nil : .infinity, minHeight: 44)
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(LinearGradient(colors: configuration.isPressed ? [Theme.accentBright, Theme.accent] : [Theme.flameTop, Theme.flameBottom], startPoint: .top, endPoint: .bottom)))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

/// A secondary action: an ink fill with an ember label.
struct QuietButtonStyle: ButtonStyle {
    var fills = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: fills ? .infinity : nil, minHeight: 44)
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(configuration.isPressed ? Theme.raised : Theme.field))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

extension View {
    /// The app's window-level look: dark, ember tint, ink ground.
    func coinboxTheme() -> some View {
        self.preferredColorScheme(.dark)
            .tint(Theme.accent)                       // buttons and links take the tint; a root foregroundStyle would flatten them to text color
            .background(Theme.background.ignoresSafeArea())
    }

    /// For a `List` or `Form`: ink ground instead of the system gray.
    func themedList() -> some View {
        self.scrollContentBackground(.hidden).background(Theme.background.ignoresSafeArea())
    }
}
