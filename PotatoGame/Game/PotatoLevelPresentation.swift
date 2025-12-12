// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Mick Schroeder, LLC.

import Foundation

/// Lightweight DTO that mirrors the level data needed by SpriteKit.
struct PotatoLevelPresentation {
    let levelNumber: Int
    let backgroundColor: PotatoColor
    let potentialPotatoCount: Int
    let ownedLevelPackIDs: Set<String>
    var objects: [PotatoGameBoardObject]

    @MainActor
    init(levelInfo: PotatoGameLevelInfo) {
        levelNumber = levelInfo.levelNumber
        backgroundColor = levelInfo.levelBackgroundColor
        potentialPotatoCount = levelInfo.potentialPotatoCount
        ownedLevelPackIDs = levelInfo.ownedLevelPackIDs
        objects = levelInfo.schmojiInLevel
    }
}
