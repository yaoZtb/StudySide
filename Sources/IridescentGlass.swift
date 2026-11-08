import SwiftUI

/// Static code-native artwork: silver ribbon with thin-film colour and reflected highlights.
struct IridescentSculpture: View {
    private let spectrum: [Color] = [
        Color(rgb: 0xC1C8D4), .white, Color(rgb: 0xC7F5EF), Color(rgb: 0xB7BBF7),
        Color(rgb: 0xF8D9E8), Color(rgb: 0xF4EFBE), .white, Color(rgb: 0x9EA6BC),
        Color(rgb: 0xDDE5F3), .white, Color(rgb: 0xC1C8D4)
    ]
    var body: some View {
        GeometryReader { geometry in
            let unit = min(geometry.size.width, geometry.size.height * 1.35)
            ZStack {
                Ellipse()
                    .fill(Color.black.opacity(0.13))
                    .frame(width: unit * 0.65, height: unit * 0.09)
                    .blur(radius: unit * 0.07).offset(y: unit * 0.31)
                RibbonOrbit()
                    .stroke(Color(rgb: 0x8B91A2).opacity(0.2), style: StrokeStyle(lineWidth: unit * 0.23, lineCap: .round))
                    .blur(radius: unit * 0.025)
                    .offset(y: unit * 0.025)
                RibbonOrbit()
                    .stroke(AngularGradient(colors: spectrum, center: .center, startAngle: .degrees(-70), endAngle: .degrees(290)),
                            style: StrokeStyle(lineWidth: unit * 0.21, lineCap: .round))
                    .shadow(color: .white.opacity(0.75), radius: unit * 0.015, x: -unit * 0.015, y: -unit * 0.02)
                RibbonOrbit()
                    .stroke(LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.04), Color(rgb: 0xADB7CE).opacity(0.65), .white.opacity(0.95)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: unit * 0.12, lineCap: .round))
                RibbonOrbit()
                    .stroke(AngularGradient(colors: [.white, .clear, .white.opacity(0.9), .clear, .white],
                                            center: .center), lineWidth: max(0.7, unit * 0.008))
                    .offset(x: -unit * 0.015, y: -unit * 0.045)
                RibbonOrbit()
                    .stroke(LinearGradient(colors: [.clear, Color(rgb: 0xC9A6EE).opacity(0.65), Color(rgb: 0x9CEDE8).opacity(0.6), .clear],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: unit * 0.025, lineCap: .round))
                    .offset(x: unit * 0.035, y: unit * 0.04)
            }
            .frame(width: unit, height: unit * 0.76)
            .rotationEffect(.degrees(-26))
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .allowsHitTesting(false)
    }
}

private struct RibbonOrbit: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.25, y: rect.height * 0.17))
        path.addCurve(to: CGPoint(x: rect.width * 0.78, y: rect.height * 0.64),
                      control1: CGPoint(x: rect.width * 0.87, y: -rect.height * 0.03),
                      control2: CGPoint(x: rect.width * 0.99, y: rect.height * 0.45))
        path.addCurve(to: CGPoint(x: rect.width * 0.23, y: rect.height * 0.36),
                      control1: CGPoint(x: rect.width * 0.39, y: rect.height * 1.04),
                      control2: CGPoint(x: rect.width * 0.01, y: rect.height * 0.76))
        path.addCurve(to: CGPoint(x: rect.width * 0.75, y: rect.height * 0.33),
                      control1: CGPoint(x: rect.width * 0.44, y: rect.height * 0.04),
                      control2: CGPoint(x: rect.width * 0.81, y: rect.height * 0.13))
        return path
    }
}

struct ThemeBackdrop: View {
    let theme: StudyTheme
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                theme.background
                if theme == .iridescent {
                    IridescentSculpture()
                        .frame(width: geometry.size.width * 1.55, height: geometry.size.height * 0.68)
                        .opacity(0.5)
                        .rotationEffect(.degrees(12))
                        .position(x: geometry.size.width * 0.82, y: geometry.size.height * 0.57)
                    LinearGradient(colors: [.white.opacity(0.22), .clear, .white.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
        }.clipped().allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct BeveledCard: InsettableShape {
    var cut: CGFloat
    var radius: CGFloat
    var inset: CGFloat = 0
    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        guard cut > 0 else { return Path(roundedRect: r, cornerRadius: radius) }
        var path = Path()
        let c = min(cut, min(r.width, r.height) / 3)
        path.move(to: CGPoint(x: r.minX + c, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c))
        path.addLine(to: CGPoint(x: r.maxX - c, y: r.maxY))
        path.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        path.addLine(to: CGPoint(x: r.minX, y: r.minY + c))
        path.closeSubpath()
        return path
    }
    func inset(by amount: CGFloat) -> Self {
        var copy = self
        copy.inset += amount
        return copy
    }
}
