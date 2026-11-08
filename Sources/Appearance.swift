import SwiftUI

extension Color {
    init(rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255)
    }
}

enum StudyTheme: String, CaseIterable, Identifiable {
    case graphite, midnight, editorial, glacier, lavender, iridescent
    var id: String { rawValue }
    var name: String {
        switch self {
        case .graphite: "Minimal Graphite"
        case .midnight: "Midnight"
        case .editorial: "Paper Study"
        case .glacier: "Glacier Blue"
        case .lavender: "Soft Lavender"
        case .iridescent: "Iridescent Glass"
        }
    }
    var subtitle: String {
        switch self {
        case .graphite: "Clean white · Quiet graphite"
        case .midnight: "Dark canvas · Indigo accents"
        case .editorial: "Warm paper · Editorial type"
        case .glacier: "Cool blue · Light and clear"
        case .lavender: "Soft gradients · Rounded details"
        case .iridescent: "Silver canvas · Iridescent glass"
        }
    }
    var canvas: Color {
        let value: UInt32 = switch self {
        case .graphite: 0xF6F6F6
        case .midnight: 0x14161D
        case .editorial: 0xF4EFE5
        case .glacier: 0xEFF5FA
        case .lavender: 0xF5F1FA
        case .iridescent: 0xD8D9DC
        }
        return Color(rgb: value)
    }
    var surface: Color {
        let value: UInt32 = switch self {
        case .graphite: 0xFFFFFF
        case .midnight: 0x20232D
        case .editorial: 0xFCF9F2
        case .glacier: 0xFFFFFF
        case .lavender: 0xFEFCFF
        case .iridescent: 0xF1F2F4
        }
        return Color(rgb: value).opacity(self == .iridescent ? 0.72 : 1)
    }
    var ink: Color { Color(rgb: self == .midnight ? 0xECEEF5 : self == .editorial ? 0x352E25 : 0x242630) }
    var accent: Color {
        let value: UInt32 = switch self {
        case .graphite: 0x34363D
        case .midnight: 0x97ACFF
        case .editorial: 0x76553A
        case .glacier: 0x286B9F
        case .lavender: 0x7B5EA7
        case .iridescent: 0x27292D
        }
        return Color(rgb: value)
    }
    var onAccent: Color { self == .midnight ? Color(rgb: 0x151926) : .white }
    var border: Color { self == .iridescent ? Color.white.opacity(0.65) : ink.opacity(self == .midnight ? 0.11 : 0.075) }
    var radius: CGFloat {
        switch self {
        case .graphite: 12
        case .midnight: 16
        case .editorial: 5
        case .glacier: 14
        case .lavender: 22
        case .iridescent: 24
        }
    }
    var design: Font.Design { self == .editorial ? .serif : self == .lavender ? .rounded : .default }
    var colorScheme: ColorScheme { self == .midnight ? .dark : .light }
    var background: LinearGradient {
        LinearGradient(colors: [canvas, self == .lavender ? Color(rgb: 0xEBEFF9) : canvas], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

private struct StudyThemeKey: EnvironmentKey {
    static let defaultValue: StudyTheme = .graphite
}
extension EnvironmentValues {
    var studyTheme: StudyTheme {
        get { self[StudyThemeKey.self] }
        set { self[StudyThemeKey.self] = newValue }
    }
}

struct AppearanceView: View {
    @ObservedObject var model: StudyModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Make it feel like you").font(.system(size: 23, weight: .semibold))
                    Text("Changes apply instantly and are saved.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(StudyTheme.allCases) { theme in
                        Button { model.themeID = theme.rawValue } label: {
                            HStack(spacing: 18) {
                                ThemeMiniature(theme: theme).frame(width: 136, height: 90).clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.border))
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(theme.name).font(.system(size: 15, weight: .semibold))
                                    Text(theme.subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: model.theme == theme ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 19)).foregroundStyle(model.theme == theme ? model.theme.accent : model.theme.ink.opacity(0.2))
                            }.padding(12).contentShape(Rectangle())
                                .background(model.theme.surface, in: RoundedRectangle(cornerRadius: 13))
                                .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(model.theme == theme ? model.theme.accent.opacity(0.65) : model.theme.border, lineWidth: model.theme == theme ? 1.5 : 1))
                        }.buttonStyle(.plain).accessibilityLabel(theme.name + (model.theme == theme ? ", selected" : ""))
                    }
                }.padding(2)
            }.scrollIndicators(.hidden)
        }.padding(24).frame(width: 490, height: 660)
            .background(ThemeBackdrop(theme: model.theme)).foregroundStyle(model.theme.ink).tint(model.theme.accent)
            .preferredColorScheme(model.theme.colorScheme)
    }
}

/// Code-native miniature used both by the picker and by visual QA.
struct ThemeMiniature: View {
    let theme: StudyTheme
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: "book").font(.system(size: 8, weight: .medium))
                Text("StudySide").font(.system(size: 7, weight: .semibold, design: theme.design))
                Spacer()
                Image(systemName: "ellipsis").font(.system(size: 8))
            }.foregroundStyle(theme.ink)
            HStack(spacing: 4) {
                Image(systemName: "macwindow").font(.system(size: 6))
                Text("Course window").font(.system(size: 5))
                Spacer()
            }.padding(5).foregroundStyle(theme.accent)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radius / 3))
            HStack {
                Spacer()
                Text("How does this step work?").font(.system(size: 5)).padding(4)
                    .background(theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: theme.radius / 3))
            }
            Text("Let's start with a simple example.").font(.system(size: 5, design: theme.design)).foregroundStyle(theme.ink)
            Spacer(minLength: 0)
            HStack {
                Capsule().fill(theme.ink.opacity(0.12)).frame(width: 53, height: 2)
                Spacer()
                Image(systemName: "arrow.up").font(.system(size: 5, weight: .bold)).foregroundStyle(theme.onAccent)
                    .frame(width: 10, height: 10).background(theme.accent, in: RoundedRectangle(cornerRadius: 3))
            }.padding(4).background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radius / 3))
        }.padding(8).background(ThemeBackdrop(theme: theme)).foregroundStyle(theme.ink)
    }
}
