// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import SwiftUI
#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

enum PotatoTheme {
    static let accent: Color = .init("AccentColor")
    static let text: Color = .init("PotatoText")
    static let secondaryText: Color = .init("PotatoSecondaryText")
    static let titleText: Color = .init("PotatoTitleText")
    static let button: Color = .init("PotatoButton")
    static let buttonText: Color = .init("PotatoButtonText")
    static let background: Color = .init("PotatoBackground")
    static let secondaryBackground: Color = .init("PotatoSecondaryBackground")
    static let tertiaryBackground: Color = .init("PotatoTertiaryBackground")
    static let cardBackground: Color = .init("PotatoCardBackground")
    static let cardText: Color = .init("PotatoCardText")
    static let cardSecondaryText: Color = .init("PotatoCardSecondaryText")
    static let border: Color = .init("PotatoBorder")
}

private struct PotatoBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(PotatoTheme.tertiaryBackground)
    }
}

private struct PotatoCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let shadowColor = PotatoTheme.border.opacity(colorScheme == .dark ? 0.6 : 0.32)

        content
            .background(
                shape
                    .fill(PotatoTheme.cardBackground)
                    .overlay {
                        shape
                            .stroke(PotatoTheme.border, lineWidth: 1)
                    }
            )
            .shadow(color: shadowColor, radius: colorScheme == .dark ? 12 : 8, x: 0, y: colorScheme == .dark ? 6 : 4)
            .foregroundStyle(PotatoTheme.cardText)
    }
}

extension View {
    func potatoBackground() -> some View {
        modifier(PotatoBackgroundModifier())
    }

    func potatoCardStyle(cornerRadius: CGFloat = 26) -> some View {
        modifier(PotatoCardModifier(cornerRadius: cornerRadius))
    }

    @ViewBuilder
    func glassedEffect(in shape: some Shape, interactive: Bool = false, tint: Color? = nil, clear: Bool = false) -> some View {
        platformGlassEffect(in: shape, interactive: interactive, tint: tint, clear: clear)
    }

    @ViewBuilder
    func glassedSurface(in shape: some Shape, interactive: Bool = false, tint: Color? = nil, clear: Bool = false) -> some View {
        glassedEffect(in: shape, interactive: interactive, tint: tint, clear: clear)
            .clipShape(shape)
            .contentShape(shape)
    }

    @ViewBuilder
    func glassedCard(cornerRadius: CGFloat = 30, interactive: Bool = false, tint: Color? = nil, clear: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        glassedSurface(in: shape, interactive: interactive, tint: tint, clear: clear)
    }

    @ViewBuilder
    func glassButtonStyle(prominent: Bool = false) -> some View {
        platformGlassButtonStyle(prominent: prominent)
    }
}

extension Shape {
    func glassed() -> some View {
        fill(.ultraThinMaterial)
            .fill(
                .linearGradient(
                    colors: [
                        .primary.opacity(0.08),
                        .primary.opacity(0.05),
                        .primary.opacity(0.01),
                        .clear,
                        .clear,
                        .clear,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .stroke(.primary.opacity(0.2), lineWidth: 0.7)
    }
}
