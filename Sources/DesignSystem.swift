import SwiftUI
import UIKit

/// Design system — "Private Intelligence".
///
/// 2026 direction distilled: a quiet graphite base, ONE electric signature
/// accent ("liquid mint", playing on the LiquidChat name), soft glass
/// surfaces, pill geometry, rounded display type, and micro-interactions that
/// communicate. Icons are Lucide (ISC) shipped as template vector assets.
enum DS {

    // MARK: - Color tokens (adaptive light/dark)

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    /// Signature accent — liquid mint. Darkened in light mode for contrast.
    static let accent = adaptive(
        light: UIColor(red: 0.04, green: 0.62, blue: 0.51, alpha: 1),   // #0A9E82
        dark:  UIColor(red: 0.24, green: 0.95, blue: 0.77, alpha: 1))   // #3DF2C4

    /// Gradient used for primary surfaces (user bubbles, hero chips).
    static let accentGradient = LinearGradient(
        colors: [
            adaptive(light: UIColor(red: 0.03, green: 0.66, blue: 0.55, alpha: 1),
                     dark:  UIColor(red: 0.24, green: 0.95, blue: 0.77, alpha: 1)),
            adaptive(light: UIColor(red: 0.05, green: 0.55, blue: 0.62, alpha: 1),
                     dark:  UIColor(red: 0.22, green: 0.78, blue: 0.93, alpha: 1)),
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Text/icon color that sits on top of the accent gradient.
    static let onAccent = adaptive(
        light: .white,
        dark:  UIColor(red: 0.04, green: 0.09, blue: 0.08, alpha: 1))   // near-black on mint

    /// App background — warm paper / deep graphite.
    static let bg = adaptive(
        light: UIColor(red: 0.97, green: 0.97, blue: 0.96, alpha: 1),   // #F7F7F5
        dark:  UIColor(red: 0.055, green: 0.06, blue: 0.06, alpha: 1))  // #0E0F0F

    /// Card / bubble surface.
    static let surface = adaptive(
        light: .white,
        dark:  UIColor(red: 0.10, green: 0.11, blue: 0.11, alpha: 1))   // #1A1C1C

    /// Raised surface (chips, secondary buttons).
    static let surfaceElevated = adaptive(
        light: UIColor(red: 0.94, green: 0.94, blue: 0.93, alpha: 1),
        dark:  UIColor(red: 0.14, green: 0.15, blue: 0.15, alpha: 1))   // #232626

    /// Hairline border on cards over glass/graphite.
    static let stroke = adaptive(
        light: UIColor(white: 0, alpha: 0.07),
        dark:  UIColor(white: 1, alpha: 0.09))

    // MARK: - Geometry

    enum Radius {
        static let s: CGFloat = 12
        static let m: CGFloat = 18
        static let l: CGFloat = 26
    }

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    // MARK: - Typography (rounded display for warmth)

    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

// MARK: - Lucide icon

/// Renders a bundled Lucide SVG (template) at a given size, tinted by the
/// current foreground style.
struct Lucide: View {
    let name: String
    var size: CGFloat = 20

    init(_ name: String, size: CGFloat = 20) {
        self.name = name
        self.size = size
    }

    var body: some View {
        Image(name)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

// MARK: - Reusable styles

/// Micro-interaction: cards and chips compress slightly under the finger.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7),
                       value: configuration.isPressed)
    }
}

/// Soft elevated card used across the app.
struct DSCard: ViewModifier {
    var radius: CGFloat = DS.Radius.m
    func body(content: Content) -> some View {
        content
            .background(DS.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(DS.stroke, lineWidth: 1))
    }
}

extension View {
    func dsCard(radius: CGFloat = DS.Radius.m) -> some View {
        modifier(DSCard(radius: radius))
    }
}
