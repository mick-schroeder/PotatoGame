// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import Foundation
import SwiftUI

struct LevelPackDefinition: Identifiable, Sendable {
    let id: String
    let productID: String
    let displayName: LocalizedStringResource
    let levelRange: ClosedRange<Int>

    var lowestLevel: Int { levelRange.lowerBound }
}

enum LevelPackRegistry {
    static let baseGameUnlockedLevels: ClosedRange<Int> = 1 ... SchmojiOptions.baseGameLevelLimit

    static let availablePacks: [LevelPackDefinition] = [
        LevelPackDefinition(
            id: "level-pack-1",
            productID: "com.mickschroeder.potatogame.levelpack",
            displayName: LocalizedStringResource.levelPack1Name,
            levelRange: 1000 ... 1999
        ),
        LevelPackDefinition(
            id: "level-pack-2",
            productID: "com.mickschroeder.potatogame.levelpack2",
            displayName: LocalizedStringResource.levelPack2Name,
            levelRange: 2000 ... 2999
        ),
    ]

    static var primaryPack: LevelPackDefinition? { availablePacks.first }

    static func productIDs() -> [String] {
        availablePacks.map(\.productID)
    }

    static func definition(forProductID productID: String) -> LevelPackDefinition? {
        availablePacks.first { $0.productID == productID }
    }

    static func definition(forLevel levelNumber: Int) -> LevelPackDefinition? {
        availablePacks.first { $0.levelRange.contains(levelNumber) }
    }
}
