import SwiftUI

/// Shared Hades Canyon inspired skull artwork used in the status bar and panel.
/// The contour is an original, simplified redraw intended to stay clear at 18 px.
struct HadesSkullSymbol: View {
    var body: some View {
        HadesSkullCutoutShape()
            .fill(Color.primary, style: FillStyle(eoFill: true))
    }
}

struct HadesSkullBrandMark: View {
    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)

            ZStack {
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.10, green: 0.15, blue: 0.23), Color(red: 0.025, green: 0.04, blue: 0.07)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                HadesSkullOuterShape()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.79, green: 0.96, blue: 1.0), Color(red: 0.18, green: 0.73, blue: 0.98), Color(red: 0.66, green: 0.36, blue: 0.83)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        HadesSkullOuterShape()
                            .stroke(Color.cyan.opacity(0.68), lineWidth: max(0.7, size * 0.018))
                    }
                    .padding(size * 0.12)
                    .shadow(color: .cyan.opacity(0.35), radius: size * 0.09)

                HadesSkullEyesShape()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 1.0, green: 0.19, blue: 0.15), Color(red: 0.87, green: 0.04, blue: 0.16)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .padding(size * 0.12)
                    .shadow(color: Color.red.opacity(0.6), radius: size * 0.045)

                HadesSkullNoseShape()
                    .fill(Color(red: 0.035, green: 0.055, blue: 0.085))
                    .padding(size * 0.12)

                HadesSkullTeethShape()
                    .stroke(Color(red: 0.035, green: 0.055, blue: 0.085), style: StrokeStyle(lineWidth: max(0.8, size * 0.035), lineCap: .round))
                    .padding(size * 0.12)
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }
}

private struct HadesSkullOuterShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: p(50, 5, rect))
        path.addCurve(to: p(16, 39, rect), control1: p(31, 5, rect), control2: p(17, 18, rect))
        path.addLine(to: p(11, 46, rect))
        path.addLine(to: p(17, 51, rect))
        path.addCurve(to: p(30, 71, rect), control1: p(17, 64, rect), control2: p(22, 68, rect))
        path.addLine(to: p(30, 86, rect))
        path.addCurve(to: p(37, 93, rect), control1: p(30, 91, rect), control2: p(33, 93, rect))
        path.addLine(to: p(63, 93, rect))
        path.addCurve(to: p(70, 86, rect), control1: p(67, 93, rect), control2: p(70, 91, rect))
        path.addLine(to: p(70, 71, rect))
        path.addCurve(to: p(83, 51, rect), control1: p(78, 68, rect), control2: p(83, 64, rect))
        path.addLine(to: p(89, 46, rect))
        path.addLine(to: p(84, 39, rect))
        path.addCurve(to: p(50, 5, rect), control1: p(83, 18, rect), control2: p(69, 5, rect))
        path.closeSubpath()
        return path
    }
}

private struct HadesSkullEyesShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: p(22, 39, rect))
        path.addLine(to: p(32, 29, rect))
        path.addLine(to: p(44, 31, rect))
        path.addLine(to: p(47, 43, rect))
        path.addLine(to: p(39, 50, rect))
        path.addLine(to: p(26, 47, rect))
        path.closeSubpath()

        path.move(to: p(78, 39, rect))
        path.addLine(to: p(68, 29, rect))
        path.addLine(to: p(56, 31, rect))
        path.addLine(to: p(53, 43, rect))
        path.addLine(to: p(61, 50, rect))
        path.addLine(to: p(74, 47, rect))
        path.closeSubpath()
        return path
    }
}

private struct HadesSkullNoseShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: p(50, 49, rect))
        path.addLine(to: p(43, 62, rect))
        path.addLine(to: p(50, 66, rect))
        path.addLine(to: p(57, 62, rect))
        path.closeSubpath()
        return path
    }
}

private struct HadesSkullTeethShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: p(38, 77, rect))
        path.addLine(to: p(38, 87, rect))
        path.move(to: p(44, 78, rect))
        path.addLine(to: p(44, 90, rect))
        path.move(to: p(50, 78, rect))
        path.addLine(to: p(50, 91, rect))
        path.move(to: p(56, 78, rect))
        path.addLine(to: p(56, 90, rect))
        path.move(to: p(62, 77, rect))
        path.addLine(to: p(62, 87, rect))
        return path
    }
}

private struct HadesSkullCutoutShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = HadesSkullOuterShape().path(in: rect)
        path.addPath(HadesSkullEyesShape().path(in: rect))
        path.addPath(HadesSkullNoseShape().path(in: rect))

        for x in [38.0, 44, 50, 56, 62] {
            path.move(to: p(x, 77, rect))
            path.addLine(to: p(x, 89, rect))
        }
        return path
    }
}

private func p(_ x: CGFloat, _ y: CGFloat, _ rect: CGRect) -> CGPoint {
    CGPoint(x: rect.minX + rect.width * x / 100, y: rect.minY + rect.height * y / 100)
}
