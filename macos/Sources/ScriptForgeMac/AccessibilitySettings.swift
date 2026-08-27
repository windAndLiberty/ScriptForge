import SwiftUI

enum InterfaceScalePolicy {
    static let storageKey = "ScriptForge.interfaceScale"
    static let minimum = 0.8
    static let maximum = 1.5
    static let step = 0.1
    static let defaultValue = 1.0

    static func normalized(_ value: Double) -> Double {
        let clamped = min(maximum, max(minimum, value))
        let snapped = (clamped / step).rounded() * step
        return min(maximum, max(minimum, snapped))
    }

    static func increase(_ value: Double) -> Double {
        normalized(value + step)
    }

    static func decrease(_ value: Double) -> Double {
        normalized(value - step)
    }

    static func percentage(_ value: Double) -> String {
        "\(Int((normalized(value) * 100).rounded()))%"
    }

    static func scaled(_ value: CGFloat, by scale: Double) -> CGFloat {
        value * normalized(scale)
    }

    /// Columns grow more gently than text and controls so enlarged type still
    /// leaves a useful editing canvas in a resizable desktop window.
    static func layoutScaled(_ value: CGFloat, by scale: Double) -> CGFloat {
        let normalizedScale = normalized(scale)
        return value * (1 + (normalizedScale - 1) * 0.5)
    }
}

private struct InterfaceScaleEnvironmentKey: EnvironmentKey {
    static let defaultValue = InterfaceScalePolicy.defaultValue
}

extension EnvironmentValues {
    var interfaceScale: Double {
        get { self[InterfaceScaleEnvironmentKey.self] }
        set { self[InterfaceScaleEnvironmentKey.self] = InterfaceScalePolicy.normalized(newValue) }
    }
}

private struct ScaledSystemFontModifier: ViewModifier {
    @Environment(\.interfaceScale) private var interfaceScale

    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    func body(content: Content) -> some View {
        content.font(.system(
            size: InterfaceScalePolicy.scaled(size, by: interfaceScale),
            weight: weight,
            design: design
        ))
    }
}

extension View {
    func scaledFont(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> some View {
        modifier(ScaledSystemFontModifier(size: size, weight: weight, design: design))
    }

    func scaledFrame(
        width: CGFloat? = nil,
        height: CGFloat? = nil,
        minWidth: CGFloat? = nil,
        maxWidth: CGFloat? = nil,
        minHeight: CGFloat? = nil,
        maxHeight: CGFloat? = nil,
        alignment: Alignment = .center
    ) -> some View {
        modifier(ScaledFrameModifier(
            width: width,
            height: height,
            minWidth: minWidth,
            maxWidth: maxWidth,
            minHeight: minHeight,
            maxHeight: maxHeight,
            alignment: alignment
        ))
    }
}

private struct ScaledFrameModifier: ViewModifier {
    @Environment(\.interfaceScale) private var interfaceScale

    let width: CGFloat?
    let height: CGFloat?
    let minWidth: CGFloat?
    let maxWidth: CGFloat?
    let minHeight: CGFloat?
    let maxHeight: CGFloat?
    let alignment: Alignment

    func body(content: Content) -> some View {
        content.frame(
            minWidth: scaled(width ?? minWidth),
            idealWidth: scaled(width),
            maxWidth: scaled(width ?? maxWidth),
            minHeight: scaled(height ?? minHeight),
            idealHeight: scaled(height),
            maxHeight: scaled(height ?? maxHeight),
            alignment: alignment
        )
    }

    private func scaled(_ value: CGFloat?) -> CGFloat? {
        value.map { InterfaceScalePolicy.scaled($0, by: interfaceScale) }
    }
}
