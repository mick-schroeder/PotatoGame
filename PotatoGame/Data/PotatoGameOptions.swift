// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import Foundation
import SwiftUI

public class PotatoGameOptions {
    /// For Testing: When true, do not save data to disk. When false, saves data to disk.
    public static let inMemoryPersistence = false

    // Default values
    public static var name: String { String(localized: "app.name") }
    public static let potatoHex: String = "1F954"
    public static let sound: Bool = true
    public static let haptics: Bool = true
    public static let gameCenter: Bool = true
    public static let showLegend: Bool = true
    public static let matchCountMin: Int = 2
    public static let baseGameLevelLimit: Int = 999
    public static let width: Int = 540
    public static let height: Int = 960
    public static let baseSizePotatoTank: Double = 90.0
    public static let baseSize: Double = 44.0
    public static let lastColor = PotatoColor.allCases.last
    public static let schmojiColorCount = PotatoColor.allCases.count
}

enum AppScreen: Codable, Hashable, Identifiable, CaseIterable {
    case levels
    case store
    case collection
    case game
    case settings
    case howto
    case potatoes
    var id: AppScreen { self }
}

extension Color {
    static var appBackground: Color {
        #if canImport(UIKit)
            Color(uiColor: .systemGroupedBackground)
        #elseif canImport(AppKit)
            Color(nsColor: .underPageBackgroundColor)
        #else
            Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 1)
        #endif
    }
}

extension Notification.Name {
    static let newGameRequested = Notification.Name("com.mickschroeder.potatogame.newGameRequested")
}
