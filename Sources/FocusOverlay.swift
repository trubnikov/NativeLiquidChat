import SwiftUI

/// Tap-to-focus overlay for the recognition camera (Google-Lens-style):
/// everything outside the focus zone is dimmed, the zone is framed with
/// scanner corner brackets, and a chip under the frame names what the camera
/// sees *there*. The zone follows the user's tap.
struct FocusOverlay: View {
    /// Center of the focus zone in screen coordinates.
    let center: CGPoint
    /// Square side of the zone on screen.
    var side: CGFloat = 210
    /// Label recognized inside the zone ("" when nothing yet).
    var label: String = ""
    /// Trained instance (accent) vs generic/none (white).
    var isTrained: Bool = false

    var body: some View {
        ZStack {
            // Dim everything outside the focus zone.
            Rectangle()
                .fill(Color.black.opacity(0.38))
                .mask {
                    Rectangle()
                        .overlay(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .frame(width: side, height: side)
                                .offset(x: center.x - side / 2, y: center.y - side / 2)
                                .blendMode(.destinationOut)
                        }
                }
                .compositingGroup()
                .allowsHitTesting(false)

            // Corner brackets: breathe softly while searching, glow when found.
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !label.isEmpty)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let breathe = label.isEmpty ? 1 + 0.015 * sin(t * 2.2) : 1.0
                CornerBrackets()
                    .stroke(bracketColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: side, height: side)
                    .scaleEffect(breathe)
                    .shadow(color: label.isEmpty ? .black.opacity(0.35)
                                                 : DS.accent.opacity(0.55),
                            radius: label.isEmpty ? 3 : 12)
            }
            .frame(width: side, height: side)
            .position(center)
            .allowsHitTesting(false)

            // Label chip under the zone: what the camera sees HERE.
            if !label.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: isTrained ? "sparkles" : "eye").font(.system(size: 13))
                    Text(label)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                }
                .foregroundColor(isTrained ? DS.onAccent : .white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .modifier(FocusChipBackground(isTrained: isTrained))
                .position(x: center.x, y: center.y + side / 2 + 26)
                .allowsHitTesting(false)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: center)
        .animation(.easeInOut(duration: 0.2), value: label)
    }

    private var bracketColor: Color {
        isTrained ? DS.accent : (label.isEmpty ? Color.white.opacity(0.85) : DS.accent)
    }
}

/// Four L-shaped scanner corners.
struct CornerBrackets: Shape {
    var cornerLength: CGFloat = 26
    var radius: CGFloat = 22

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let l = cornerLength
        let r = radius

        // Top-left
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + l))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r),
                 radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + l, y: rect.minY))
        // Top-right
        p.move(to: CGPoint(x: rect.maxX - l, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r),
                 radius: r, startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + l))
        // Bottom-right
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - l))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
                 radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX - l, y: rect.maxY))
        // Bottom-left
        p.move(to: CGPoint(x: rect.minX + l, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
                 radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - l))
        return p
    }
}

/// Chip surface: recognized objects get accent-tinted Liquid Glass (iOS 26+),
/// unknown zones a clear glass over the camera feed. Material fallback earlier.
private struct FocusChipBackground: ViewModifier {
    let isTrained: Bool
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(isTrained ? .regular.tint(DS.accent.opacity(0.7)) : .regular,
                                in: Capsule())
        } else {
            content
                .background(
                    Capsule().fill(isTrained ? AnyShapeStyle(DS.accentGradient)
                                             : AnyShapeStyle(Color.black.opacity(0.6))))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
        }
    }
}
