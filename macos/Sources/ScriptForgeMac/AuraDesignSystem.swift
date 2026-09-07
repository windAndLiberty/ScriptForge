import AppKit
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "ScriptForge.appAppearance"

    var id: String { rawValue }
    var titleKey: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }
    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.stars.fill"
        }
    }
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum AuraSurfaceLevel {
    case sidebar
    case header
    case panel
    case elevated
    case editor

    var material: Material {
        switch self {
        case .sidebar, .header: .regularMaterial
        case .panel: .thinMaterial
        case .elevated: .regularMaterial
        case .editor: .thickMaterial
        }
    }

    var tint: Color {
        switch self {
        case .sidebar: .sidebar
        case .header, .panel: .panel
        case .elevated: .surfaceElevated
        case .editor: .editorPaper
        }
    }

    var opaqueTint: Color {
        switch self {
        case .sidebar: .sidebarOpaque
        case .header, .panel: .panelOpaque
        case .elevated: .surfaceElevatedOpaque
        case .editor: .editorPaperOpaque
        }
    }
}

struct AuraRenderingPolicy: Equatable {
    let reduceMotion: Bool
    let reduceTransparency: Bool
    let applicationIsActive: Bool
    let increasedContrast: Bool

    init(
        reduceMotion: Bool,
        reduceTransparency: Bool,
        applicationIsActive: Bool,
        increasedContrast: Bool = false
    ) {
        self.reduceMotion = reduceMotion
        self.reduceTransparency = reduceTransparency
        self.applicationIsActive = applicationIsActive
        self.increasedContrast = increasedContrast
    }

    var pausesAnimation: Bool { reduceMotion || !applicationIsActive }
    var usesTranslucentSurfaces: Bool { !reduceTransparency }
    var interactionAnimationDuration: Double? { reduceMotion ? nil : 0.16 }
    var borderWidth: CGFloat { increasedContrast ? 2 : 1 }
}

struct AuraSurface: View {
    let level: AuraSurfaceLevel
    var cornerRadius: CGFloat = 0
    var showsBorder = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            if !reduceTransparency {
                shape.fill(level.material)
            }
            shape.fill(reduceTransparency ? level.opaqueTint : level.tint)
            if showsBorder {
                shape.stroke(
                    Color.border,
                    lineWidth: colorSchemeContrast == .increased ? 2 : 1
                )
            }
        }
    }
}

struct AuraBackground: View {
    let pointerLocation: CGPoint

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let policy = AuraRenderingPolicy(
            reduceMotion: reduceMotion,
            reduceTransparency: reduceTransparency,
            applicationIsActive: scenePhase == .active,
            increasedContrast: colorSchemeContrast == .increased
        )
        GeometryReader { proxy in
            if !policy.usesTranslucentSurfaces {
                Color.workspaceOpaque
            } else {
                TimelineView(.animation(
                    minimumInterval: 1.0 / 20.0,
                    paused: policy.pausesAnimation
                )) { timeline in
                    let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                    auraLayer(size: proxy.size, time: time)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func auraLayer(size: CGSize, time: TimeInterval) -> some View {
        if #available(macOS 15.0, *) {
            MeshGradient(
                width: 3,
                height: 3,
                points: meshPoints(size: size, time: time),
                colors: meshColors,
                background: Color.auraBase,
                smoothsColors: true
            )
            .overlay(Color.auraVeil)
            .animation(reduceMotion ? nil : .easeOut(duration: 1.6), value: pointerLocation)
        } else {
            radialFallback(size: size, time: time)
        }
    }

    @available(macOS 15.0, *)
    private func meshPoints(size: CGSize, time: TimeInterval) -> [SIMD2<Float>] {
        let pointer = normalizedPointer(in: size)
        let xInfluence = Float((pointer.x - 0.5) * 0.045)
        let yInfluence = Float((pointer.y - 0.5) * 0.045)
        let slow = Float(time / 18)
        return [
            SIMD2(0, 0), SIMD2(0.5 + sin(slow) * 0.035, 0), SIMD2(1, 0),
            SIMD2(0, 0.5 + cos(slow * 0.73) * 0.04),
            SIMD2(0.5 + sin(slow * 0.81) * 0.07 + xInfluence,
                  0.5 + cos(slow * 0.61) * 0.06 + yInfluence),
            SIMD2(1, 0.5 + sin(slow * 0.52) * 0.04),
            SIMD2(0, 1), SIMD2(0.5 + cos(slow * 0.67) * 0.035, 1), SIMD2(1, 1),
        ]
    }

    private var meshColors: [Color] {
        if colorScheme == .dark {
            return [
                .auraInk, .auraIndigoMuted, .auraBlueMuted,
                .auraPurpleMuted, .auraInk, .auraCoralMuted,
                .auraBlueMuted, .auraVioletMuted, .auraInk,
            ]
        }
        return [
            .auraDawn, .auraBlueMist, .auraDawn,
            .auraPurpleMist, .auraDawn, .auraCoralMist,
            .auraDawn, .auraBlueMist, .auraDawn,
        ]
    }

    private func radialFallback(size: CGSize, time: TimeInterval) -> some View {
        let pointer = normalizedPointer(in: size)
        let pointerOffset = CGSize(
            width: (pointer.x - 0.5) * 12,
            height: (pointer.y - 0.5) * 12
        )
        let slow = time / 20
        return ZStack {
            Color.auraBase
            auraBlob(
                color: .auraBlue,
                diameter: max(size.width * 0.68, 620),
                position: CGPoint(
                    x: size.width * 0.74 + sin(slow) * 38 + pointerOffset.width,
                    y: size.height * 0.18 + cos(slow * 0.7) * 28 + pointerOffset.height
                )
            )
            auraBlob(
                color: .auraViolet,
                diameter: max(size.width * 0.62, 560),
                position: CGPoint(
                    x: size.width * 0.28 + cos(slow * 0.64) * 44 - pointerOffset.width * 0.7,
                    y: size.height * 0.72 + sin(slow * 0.58) * 32 - pointerOffset.height * 0.7
                )
            )
            auraBlob(
                color: .auraCoral,
                diameter: max(size.width * 0.44, 430),
                position: CGPoint(
                    x: size.width * 0.84 + sin(slow * 0.47) * 28,
                    y: size.height * 0.78 + cos(slow * 0.52) * 24
                )
            )
            Color.auraVeil
        }
        .drawingGroup()
        .animation(reduceMotion ? nil : .easeOut(duration: 1.6), value: pointerLocation)
    }

    private func auraBlob(color: Color, diameter: CGFloat, position: CGPoint) -> some View {
        Circle()
            .fill(RadialGradient(
                colors: [color.opacity(colorScheme == .dark ? 0.34 : 0.22), color.opacity(0)],
                center: .center,
                startRadius: 0,
                endRadius: diameter * 0.5
            ))
            .frame(width: diameter, height: diameter)
            .blur(radius: 84)
            .position(position)
    }

    private func normalizedPointer(in size: CGSize) -> CGPoint {
        guard size.width > 0, size.height > 0, pointerLocation != .zero else {
            return CGPoint(x: 0.5, y: 0.5)
        }
        return CGPoint(
            x: min(max(pointerLocation.x / size.width, 0), 1),
            y: min(max(pointerLocation.y / size.height, 0), 1)
        )
    }
}

private struct PointingHandCursorModifier: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        content.onHover { hovering in
            guard enabled else { return }
            if hovering {
                NSCursor.pointingHand.set()
            } else if NSCursor.current == NSCursor.pointingHand {
                NSCursor.arrow.set()
            }
        }
    }
}

extension View {
    func pointingHandCursor(enabled: Bool = true) -> some View {
        modifier(PointingHandCursorModifier(enabled: enabled))
    }

    func auraSurface(
        _ level: AuraSurfaceLevel = .panel,
        cornerRadius: CGFloat = 12,
        showsBorder: Bool = true
    ) -> some View {
        background {
            AuraSurface(level: level, cornerRadius: cornerRadius, showsBorder: showsBorder)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    func panelCard() -> some View {
        modifier(ScaledPanelCardModifier())
    }

    func auraTextEditor() -> some View {
        scrollContentBackground(.hidden)
            .foregroundStyle(Color.primaryText)
            .tint(Color.brand)
    }
}

private struct ScaledPanelCardModifier: ViewModifier {
    @Environment(\.interfaceScale) private var interfaceScale

    func body(content: Content) -> some View {
        content
            .padding(InterfaceScalePolicy.scaled(14, by: interfaceScale))
            .frame(maxWidth: .infinity, alignment: .leading)
            .auraSurface(
                .panel,
                cornerRadius: InterfaceScalePolicy.scaled(12, by: interfaceScale)
            )
    }
}

private struct AuraButtonBody<Label: View>: View {
    enum Kind { case primary, secondary, icon }

    let label: Label
    let kind: Kind
    let isPressed: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.interfaceScale) private var interfaceScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @State private var isHovered = false

    var body: some View {
        label
            .scaledFont(size: kind == .primary ? 12 : 11, weight: .semibold)
            .foregroundStyle(kind == .primary ? Color.white : Color.primaryText)
            .padding(
                .horizontal,
                kind == .icon ? 0 : scaled(kind == .primary ? 15 : 12)
            )
            .frame(
                width: kind == .icon ? scaled(32) : nil,
                height: kind == .icon ? scaled(32) : nil
            )
            .frame(minHeight: kind == .icon ? nil : scaled(kind == .primary ? 35 : 32))
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(
                        kind == .primary ? Color.white.opacity(0.13) : Color.border,
                        lineWidth: colorSchemeContrast == .increased ? 2 : 1
                    )
            }
            .shadow(
                color: kind == .primary && isHovered ? Color.auraCoral.opacity(0.24) : .clear,
                radius: 13,
                y: 4
            )
            .scaleEffect(reduceMotion ? 1 : (isPressed ? 0.985 : (isHovered && isEnabled ? 1.01 : 1)))
            .opacity(isEnabled ? 1 : 0.48)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isHovered)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: isPressed)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .pointingHandCursor(enabled: isEnabled)
    }

    private func scaled(_ value: CGFloat) -> CGFloat {
        InterfaceScalePolicy.scaled(value, by: interfaceScale)
    }

    @ViewBuilder private var background: some View {
        if kind == .primary {
            LinearGradient(
                colors: isPressed
                    ? [Color.auraViolet.opacity(0.78), Color.brand.opacity(0.82)]
                    : [Color.auraViolet, Color.brand],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            AuraSurface(level: isHovered ? .elevated : .panel, cornerRadius: 9)
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        AuraButtonBody(label: configuration.label, kind: .primary, isPressed: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        AuraButtonBody(label: configuration.label, kind: .secondary, isPressed: configuration.isPressed)
    }
}

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        AuraButtonBody(label: configuration.label, kind: .icon, isPressed: configuration.isPressed)
    }
}

struct AuraPlainButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        AuraPlainButtonBody(label: configuration.label, isPressed: configuration.isPressed)
    }
}

private struct AuraPlainButtonBody<Label: View>: View {
    let label: Label
    let isPressed: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        label
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(isHovered && isEnabled ? 0.035 : 0))
            }
            .opacity(isEnabled ? (isPressed ? 0.72 : 1) : 0.48)
            .scaleEffect(reduceMotion ? 1 : (isPressed ? 0.995 : 1))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovered)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .pointingHandCursor(enabled: isEnabled)
    }
}

extension Color {
    static let brand = adaptive(
        light: NSColor(srgbRed: 0.77, green: 0.20, blue: 0.25, alpha: 1),
        dark: NSColor(srgbRed: 1.00, green: 0.38, blue: 0.48, alpha: 1)
    )
    static let brandLight = adaptive(
        light: NSColor(srgbRed: 0.90, green: 0.38, blue: 0.31, alpha: 1),
        dark: NSColor(srgbRed: 1.00, green: 0.62, blue: 0.52, alpha: 1)
    )

    static let auraBlue = Color(red: 0.20, green: 0.48, blue: 0.96)
    static let auraViolet = Color(red: 0.55, green: 0.36, blue: 0.96)
    static let auraCoral = Color(red: 1.00, green: 0.39, blue: 0.49)

    static let auraBase = adaptive(
        light: NSColor(srgbRed: 0.94, green: 0.94, blue: 0.97, alpha: 1),
        dark: NSColor(srgbRed: 0.027, green: 0.039, blue: 0.071, alpha: 1)
    )
    static let auraVeil = adaptive(
        light: NSColor(srgbRed: 0.98, green: 0.97, blue: 0.95, alpha: 0.34),
        dark: NSColor(srgbRed: 0.02, green: 0.025, blue: 0.055, alpha: 0.38)
    )

    static let sidebar = adaptive(
        light: NSColor(srgbRed: 0.055, green: 0.067, blue: 0.11, alpha: 0.82),
        dark: NSColor(srgbRed: 0.035, green: 0.045, blue: 0.085, alpha: 0.70)
    )
    static let sidebarOpaque = Color(red: 0.045, green: 0.052, blue: 0.09)
    static let workspace = adaptive(
        light: NSColor(srgbRed: 0.96, green: 0.955, blue: 0.94, alpha: 0.53),
        dark: NSColor(srgbRed: 0.035, green: 0.045, blue: 0.078, alpha: 0.43)
    )
    static let workspaceOpaque = adaptive(
        light: NSColor(srgbRed: 0.95, green: 0.945, blue: 0.93, alpha: 1),
        dark: NSColor(srgbRed: 0.035, green: 0.043, blue: 0.068, alpha: 1)
    )
    static let panel = adaptive(
        light: NSColor(srgbRed: 1.0, green: 0.99, blue: 0.975, alpha: 0.64),
        dark: NSColor(srgbRed: 0.075, green: 0.088, blue: 0.14, alpha: 0.62)
    )
    static let panelOpaque = adaptive(
        light: NSColor(srgbRed: 0.985, green: 0.98, blue: 0.965, alpha: 1),
        dark: NSColor(srgbRed: 0.075, green: 0.085, blue: 0.12, alpha: 1)
    )
    static let surfaceElevated = adaptive(
        light: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.76),
        dark: NSColor(srgbRed: 0.105, green: 0.12, blue: 0.18, alpha: 0.72)
    )
    static let surfaceElevatedOpaque = adaptive(
        light: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
        dark: NSColor(srgbRed: 0.105, green: 0.115, blue: 0.16, alpha: 1)
    )
    static let editorPaper = adaptive(
        light: NSColor(srgbRed: 1, green: 0.995, blue: 0.98, alpha: 0.92),
        dark: NSColor(srgbRed: 0.055, green: 0.063, blue: 0.09, alpha: 0.91)
    )
    static let editorPaperOpaque = adaptive(
        light: NSColor(srgbRed: 1, green: 0.995, blue: 0.98, alpha: 1),
        dark: NSColor(srgbRed: 0.055, green: 0.063, blue: 0.09, alpha: 1)
    )
    static let border = adaptive(
        light: NSColor(srgbRed: 0.08, green: 0.09, blue: 0.13, alpha: 0.11),
        dark: NSColor(srgbRed: 0.85, green: 0.88, blue: 1.0, alpha: 0.12)
    )
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary

    fileprivate static let auraInk = Color(red: 0.027, green: 0.039, blue: 0.071)
    fileprivate static let auraDawn = Color(red: 0.95, green: 0.94, blue: 0.92)
    fileprivate static let auraIndigoMuted = Color(red: 0.09, green: 0.10, blue: 0.25)
    fileprivate static let auraBlueMuted = Color(red: 0.035, green: 0.13, blue: 0.25)
    fileprivate static let auraPurpleMuted = Color(red: 0.18, green: 0.07, blue: 0.24)
    fileprivate static let auraVioletMuted = Color(red: 0.15, green: 0.10, blue: 0.29)
    fileprivate static let auraCoralMuted = Color(red: 0.24, green: 0.075, blue: 0.12)
    fileprivate static let auraBlueMist = Color(red: 0.78, green: 0.86, blue: 0.98)
    fileprivate static let auraPurpleMist = Color(red: 0.90, green: 0.82, blue: 0.97)
    fileprivate static let auraCoralMist = Color(red: 0.98, green: 0.82, blue: 0.80)

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua ? dark : light
        })
    }
}
