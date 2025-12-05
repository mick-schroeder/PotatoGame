// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import Foundation
import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

public enum SchmojiColor: String, Codable, CaseIterable, Hashable, ShapeStyle {
    case green = "Green"
    case yellow = "Yellow"
    case orange = "Orange"
    case red = "Red"
    case purple = "Purple"
    case blue = "Blue"
    case pink = "Pink"
    case brown = "Brown"

    public var schmojiColor: Color {
        switch self {
        case .blue: Color.schmojiBlue
        case .green: Color.schmojiGreen
        case .orange: Color.schmojiOrange
        case .purple: Color.schmojiPurple
        case .red: Color.schmojiRed
        case .pink: Color.schmojiPink
        case .yellow: Color.schmojiYellow
        case .brown: Color.schmojiBrown
        }
    }

    public var systemColor: Color {
        switch self {
        case .blue: .blue
        case .green: .green
        case .orange: .orange
        case .purple: .purple
        case .red: .red
        case .pink: .pink
        case .yellow: .yellow
        case .brown: .brown
        }
    }

    public var localizedName: LocalizedStringResource {
        switch self {
        case .green:
            LocalizedStringResource.schmojiColorGreen
        case .yellow:
            LocalizedStringResource.schmojiColorYellow
        case .orange:
            LocalizedStringResource.schmojiColorOrange
        case .red:
            LocalizedStringResource.schmojiColorRed
        case .purple:
            LocalizedStringResource.schmojiColorPurple
        case .blue:
            LocalizedStringResource.schmojiColorBlue
        case .pink:
            LocalizedStringResource.schmojiColorPink
        case .brown:
            LocalizedStringResource.schmojiColorBrown
        }
    }

    public var color: Color {
        Color("Schmoji\(rawValue)")
    }

    public var order: Int {
        switch self {
        case .green: 1
        case .yellow: 2
        case .orange: 3
        case .red: 4
        case .purple: 5
        case .blue: 6
        case .pink: 7
        case .brown: 8
        }
    }

    public var size: Double {
        // Golden ratio derivation
        let phi = (1.0 + sqrt(5.0)) / 2.0

        // Adjust the exponent to control the size scaling
        let exponent = 0.4

        // Calculate size using the adjusted scaling
        return SchmojiOptions.baseSize * pow(phi, Double(order - 1) * exponent)
    }

    public var schmojis: [String] {
        switch self {
        case .blue: ["1F40B", "1F456", "1F48E", "1F699", "1F6F8", "1F976", "1F9CA", "1F41F", "1FA72", "1F4A6", "1F9F6", "1FA79"]
        case .brown: ["1F954"]
        case .green: ["1F340", "1F422", "1F438", "1F966", "1F96C", "1F996", "1F432", "1F951", "1F922", "1F333", "1F58D FE0F", "1F69C", "1F335", "1F378", "1F986"]
        case .orange: ["1F351", "1F525", "1F42F", "1F34A", "1F357", "1F415", "1F431", "1F436", "1F439", "1F955", "1F983", "1F379", "1F981", "1F681", "1F360"]
        case .pink: ["1F980", "1F338", "1F437", "1F498", "1F9A9", "1F9C1", "1F9E0", "1F9FC", "1F45A", "1FA71", "1F414", "1F435"]
        case .purple: ["1F346", "1F347", "1F47E", "1F52E", "1F97C", "1F43C", "1F5A4", "1F47F", "1FABB", "1FAD0", "1F64F", "2602 FE0F", "1F3F4 200D 2620 FE0F", "231A"]
        case .red: ["1F336", "2764 FE0F", "1F36C", "1F34E", "1F353", "1F3B8", "1F444", "1F479", "1F680", "1F969", "1F621", "1F45B", "1F339", "1F380"]
        case .yellow: ["1F34C", "1F355", "1F44E", "1F90C", "1F918", "1F9B6", "1F44D", "1F44C", "1F4A1", "1F4AA", "1F603", "1F60E", "1F618", "1F424", "1F602", "1F92F"]
        }
    }

    public func nextColor() -> SchmojiColor {
        let cases = SchmojiColor.allCases
        guard let idx = cases.firstIndex(of: self) else { return .green }
        // If we're already at the last element, stay on it (clamped)
        let lastIndex = cases.index(before: cases.endIndex)
        if idx == lastIndex { return cases[idx] }
        let nextIndex = cases.index(after: idx)
        return cases[nextIndex]
    }

    public func previousColor() -> SchmojiColor {
        let cases = SchmojiColor.allCases
        guard let idx = cases.firstIndex(of: self) else { return .green }
        // If we're already at the first element, stay on it (clamped)
        if idx == cases.startIndex { return cases[idx] }
        let prevIndex = cases.index(before: idx)
        return cases[prevIndex]
    }
}

extension SchmojiColor: Identifiable {
    public var id: RawValue { rawValue }
}

public extension SchmojiColor {
    init?(order: Int) {
        guard let color = SchmojiColor.allCases.first(where: { $0.order == order }) else {
            return nil
        }
        self = color
    }
}

extension Color {
    func lightened(amount: CGFloat, colorScheme: ColorScheme) -> Color {
        adjusted(toward: .white, amount: amount, colorScheme: colorScheme)
    }

    func darkened(amount: CGFloat, colorScheme: ColorScheme) -> Color {
        adjusted(toward: .black, amount: amount, colorScheme: colorScheme)
    }

    func adjusted(toward target: Color, amount: CGFloat, colorScheme: ColorScheme) -> Color {
        let ratio = max(0, min(1, amount))

        #if canImport(UIKit)
            let trait = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
            let baseColor = UIColor(self).resolvedColor(with: trait)
            let targetColor = UIColor(target).resolvedColor(with: trait)
            guard let start = baseColor.rgbaComponents, let end = targetColor.rgbaComponents else {
                return self
            }
            let blended = RGBA(
                red: start.red + (end.red - start.red) * ratio,
                green: start.green + (end.green - start.green) * ratio,
                blue: start.blue + (end.blue - start.blue) * ratio,
                alpha: start.alpha + (end.alpha - start.alpha) * ratio
            )
            return Color(uiColor: blended.platformColor)
        #elseif canImport(AppKit)
            let appearance: NSAppearance? = if #available(macOS 10.14, *) {
                NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
            } else {
                nil
            }
            let baseColor = NSColor(self)
            let resolvedBase = baseColor.resolved(using: appearance)
            let targetColor = NSColor(target)
            let resolvedTarget = targetColor.resolved(using: appearance)
            guard let start = resolvedBase.rgbaComponents, let end = resolvedTarget.rgbaComponents else {
                return self
            }
            let blended = RGBA(
                red: start.red + (end.red - start.red) * ratio,
                green: start.green + (end.green - start.green) * ratio,
                blue: start.blue + (end.blue - start.blue) * ratio,
                alpha: start.alpha + (end.alpha - start.alpha) * ratio
            )
            return Color(nsColor: blended.platformColor)
        #else
            return self
        #endif
    }
}

#if canImport(AppKit)
    extension NSColor {
        func resolved(using appearance: NSAppearance?) -> NSColor {
            guard let appearance else { return self }
            var resolved = self
            appearance.performAsCurrentDrawingAppearance {
                resolved = self
            }
            return resolved
        }
    }
#endif

private struct RGBA {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat

    #if canImport(UIKit)
        var platformColor: UIColor {
            UIColor(red: red, green: green, blue: blue, alpha: alpha)
        }

    #elseif canImport(AppKit)
        var platformColor: NSColor {
            NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
        }
    #endif
}

#if canImport(UIKit)
    private extension UIColor {
        var rgbaComponents: RGBA? {
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
            return RGBA(red: red, green: green, blue: blue, alpha: alpha)
        }
    }

#elseif canImport(AppKit)
    private extension NSColor {
        var rgbaComponents: RGBA? {
            guard let converted = usingColorSpace(.sRGB) else { return nil }
            return RGBA(
                red: converted.redComponent,
                green: converted.greenComponent,
                blue: converted.blueComponent,
                alpha: converted.alphaComponent
            )
        }
    }
#endif
